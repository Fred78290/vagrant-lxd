#
# Copyright (c) 2017 Catalyst.net Ltd
#
# This file is part of vagrant-lxd.
#
# vagrant-lxd is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at
# your option) any later version.
#
# vagrant-lxd is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with vagrant-lxd. If not, see <http://www.gnu.org/licenses/>.
#

require 'hyperkit'
require 'securerandom'
require 'tempfile'
require 'timeout'
require 'vagrant/machine_state'

module VagrantLXD
  class Driver
    include Vagrant::Util

    VAGRANT_UID = 1000 # TODO Make this configurable.

    class OperationTimeout < Vagrant::Errors::VagrantError
      error_key 'lxd_operation_timeout'
    end

    class NetworkAddressAcquisitionTimeout < OperationTimeout
      error_key 'lxd_network_address_acquisition_timeout'
    end

    class ConnectionFailure < Vagrant::Errors::ProviderNotUsable
      error_key 'lxd_connection_failure'
    end

    class AuthenticationFailure < Vagrant::Errors::ProviderNotUsable
      error_key 'lxd_authentication_failure'
    end

    class ContainerCreationFailure < Vagrant::Errors::VagrantError
      error_key 'lxd_container_creation_failure'
    end

    class ImageCreationFailure < ContainerCreationFailure
      error_key 'lxd_image_creation_failure'
    end

    class ContainerNotFound < Vagrant::Errors::VagrantError
      error_key 'lxd_container_not_found'
    end

    class DuplicateAttachmentFailure < Vagrant::Errors::VagrantError
      error_key 'lxd_duplicate_attachment_failure'
    end

    NOT_CREATED = Vagrant::MachineState::NOT_CREATED_ID

    attr_reader :api_endpoint
    attr_reader :timeout

    def initialize(machine)
      @machine = machine
      @timeout = machine.provider_config.timeout
      @api_endpoint = machine.provider_config.api_endpoint
      @logger = Log4r::Logger.new('vagrant::lxd')
      @lxd = Hyperkit::Client.new(api_endpoint: api_endpoint.to_s, verify_ssl: false)
    end

    def machine_id
      @machine.id
    end

    def validate!
      raise error(ConnectionFailure) unless connection_usable?
      raise error(AuthenticationFailure) unless authentication_usable?
    end

    def connection_usable?
      @lxd.images
    rescue Faraday::ConnectionFailed
      false
    else
      true
    end

    def authentication_usable?
      connection_usable? and @lxd.containers
    rescue Hyperkit::Forbidden
      false
    else
      true
    end

    def synced_folders_usable?
      # Check whether we've registered an idmap for the current user.
      if map = container[:config][:'raw.idmap']
        true if map =~ /^uid #{Process.uid} #{VAGRANT_UID}$/
      end
    rescue Vagrant::Errors::ProviderNotUsable
      false
    end

    def mount(name, options)
      container = @lxd.container(machine_id)
      devices = container[:devices].to_hash
      devices[name] = { type: 'disk', path: options[:guestpath], source: options[:hostpath] }
      container[:devices] = devices
      @lxd.update_container(machine_id, container)
    end

    def unmount(name, options)
      container = @lxd.container(machine_id)
      devices = container[:devices].to_hash
      devices.delete(name)
      container[:devices] = devices
      @lxd.update_container(machine_id, container)
    end

    def attach(container)
      @lxd.container(container) # Query LXD to make sure the container exists.

      if in_state? NOT_CREATED
        @machine.id = container
      else
        fail DuplicateAttachmentFailure, machine_name: @machine.name, container: container
      end
    rescue Hyperkit::NotFound
      @machine.ui.error "Container doesn't exist: #{container}"
      fail ContainerNotFound, container: container
    end

    def detach
      @machine.id = nil
    end

    def container
      @lxd.container(machine_id)
    end

    def state
      return NOT_CREATED if machine_id.nil?
      container_state = @lxd.container_state(machine_id)
      container_state[:status].downcase.to_sym
    rescue Hyperkit::NotFound
      NOT_CREATED
    end

    def create
      if in_state? NOT_CREATED
        machine_id = generate_machine_id
        file, fingerprint = prepare_image_file

        begin
          image = @lxd.image(fingerprint)
          @logger.debug 'Using image: ' << image.inspect
        rescue Hyperkit::NotFound
          image = @lxd.create_image_from_file(file)
          image_alias = @lxd.create_image_alias(fingerprint, machine_id)
          @logger.debug 'Created image: ' << image.inspect
          @logger.debug 'Created image alias: ' << image_alias.inspect
        end

        container = @lxd.create_container(machine_id, fingerprint: fingerprint, config: config)
        @logger.debug 'Created container: ' << container.inspect

        @machine.id = machine_id
      end
    rescue Hyperkit::BadRequest
      @lxd.delete_container(id) rescue nil unless container.nil?
      @lxd.delete_image(image[:metadata][:fingerprint]) rescue nil unless image.nil?
      @machine.ui.error 'Failed to create container'
      fail ContainerCreationFailure, machine_name: @machine.name
    end

    def resume
      case state
      when :stopped
        @lxd.start_container(machine_id)
      when :frozen
        @lxd.unfreeze_container(machine_id, timeout: timeout)
      end
    rescue Hyperkit::BadRequest
      @machine.ui.warn "Container failed to start within #{timeout} seconds"
      fail OperationTimeout, time_limit: timeout, operation: 'start', machine_id: machine_id
    end

    def halt
      if in_state? :running, :frozen
        @lxd.stop_container(machine_id, timeout: timeout)
      end
    rescue Hyperkit::BadRequest
      @machine.ui.warn "Container failed to stop within #{timeout} seconds, forcing shutdown..."
      @lxd.stop_container(machine_id, timeout: timeout, force: true)
    end

    def suspend
      if in_state? :running
        @lxd.freeze_container(machine_id, timeout: timeout)
      end
    rescue Hyperkit::BadRequest
      @machine.ui.warn "Container failed to suspend within #{timeout} seconds"
      fail OperationTimeout, time_limit: timeout, operation: 'info', machine_id: machine_id
    end

    def destroy
      if in_state? :stopped
        delete_image
        delete_container
      else
        @logger.debug "Skipped container destroy (#{machine_id} is not stopped)"
      end
    end

    def info
      if in_state? :running, :frozen
        {
          host: ipv4_address,
          port: ipv4_port,
        }
      end
    end

  protected

    def delete_container
      @lxd.delete_container(machine_id)
    rescue Hyperkit::NotFound
      @logger.warn "Container '#{machine_id}' not found, unable to destroy"
    end

    def delete_image
      @lxd.delete_image(container[:config][:'volatile.base_image'])
    rescue Hyperkit::NotFound
      @logger.warn "Image for '#{machine_id}' not found, unable to destroy"
    rescue Hyperkit::BadRequest
      @logger.error "Unable to delete image for '#{machine_id}'"
    end

  private

    def in_state?(*any)
      any.include?(state)
    end

    def ipv4_port
      22
    end

    def ipv4_address
      @logger.debug "Looking up ipv4 address for #{machine_id}..."
      Timeout.timeout(timeout) do
        loop do
          container_state = @lxd.container_state(machine_id)
          if address = container_state[:network][:eth0][:addresses].find { |a| a[:family] == 'inet' }
            return address[:address]
          else
            @logger.debug 'No ipv4 address found, sleeping 1s before trying again...'
            sleep(1)
          end
        end
      end
    rescue Timeout::Error
      @logger.warn "Failed to find ipv4 address for #{machine_id} within #{timeout} seconds!"
      fail NetworkAddressAcquisitionTimeout, time_limit: timeout, lxd_bridge: 'lxdbr0' # FIXME Hardcoded bridge name
    end

    def config
      config = {}

      # Set "raw.idmap" if the host's sub{u,g}id configuration allows it.
      # This allows sharing folders via LXD (see synced_folder.rb).
      begin
        %w(uid gid).each do |type|
          value = Process.send(type)
          if File.readlines("/etc/sub#{type}").grep(/^root:#{value}:[1-9]/).any?
            config[:'raw.idmap'] ||= ''
            config[:'raw.idmap'] << "#{type} #{value} #{VAGRANT_UID}\n"
          end
        end
      rescue StandardError => e
        @logger.warn "Cannot read subordinate permissions file: #{e.message}"
      end

      @logger.debug 'Resulting configuration: ' << config.inspect

      config
    end

    def prepare_image_file
      tmpdir = Dir.mktmpdir

      lxc_dir = @machine.box.directory
      lxc_rootfs = lxc_dir / 'rootfs.tar.gz'
      lxc_fingerprint = Digest::SHA256.file(lxc_rootfs).hexdigest

      lxd_dir = @machine.box.directory / '..' / 'lxd'
      lxd_rootfs = lxd_dir / 'rootfs.tar.gz'
      lxd_metadata = YAML.load(File.read(lxd_dir / 'metadata.yaml')) rescue nil

      unless lxd_rootfs.exist? and lxd_metadata.is_a? Hash and lxd_metadata['source_fingerprint'] == lxc_fingerprint
        @machine.ui.info 'Converting LXC image to LXD format...'

        SafeChdir.safe_chdir(tmpdir) do
          FileUtils.cp(lxc_rootfs, tmpdir)

          File.open('metadata.yaml', 'w') do |metadata|
            metadata.puts 'architecture: ' << `uname -m`.strip
            metadata.puts 'creation_date: ' << Time.now.strftime('%s')
            metadata.puts 'source_fingerprint: ' << lxc_fingerprint
          end

          Subprocess.execute('gunzip', 'rootfs.tar.gz')
          Subprocess.execute('tar', '-rf', 'rootfs.tar', 'metadata.yaml')
          Subprocess.execute('gzip', 'rootfs.tar')

          FileUtils.mkdir_p(lxd_dir)
          FileUtils.mv('rootfs.tar.gz', lxd_dir)
          FileUtils.mv('metadata.yaml', lxd_dir)
        end
      end

      return lxd_rootfs, Digest::SHA256.file(lxd_rootfs).hexdigest
    rescue Exception => e
      @machine.ui.error 'Failed to create LXD image for container'
      @logger.error 'Error preparing LXD image: ' << e.message << "\n" << e.backtrace.join("\n")
      fail ImageCreationFailure, machine_name: @machine.name, error_message: e.message
    ensure
      FileUtils.rm_rf(tmpdir)
    end

    def generate_machine_id
      id = "vagrant-#{File.basename(Dir.pwd)}-#{@machine.name}-#{SecureRandom.hex(8)}"
      id = id.slice(0...63).gsub(/[^a-zA-Z0-9]/, '-')
      id
    end

    def error(klass)
      klass.new(
        provider: Version::NAME,
        machine: @machine.name,
        api_endpoint: @api_endpoint.to_s,
        https_address: @api_endpoint.host,
        client_cert: File.expand_path('.config/lxc/client.crt', ENV['HOME']),
      )
    end
  end
end
