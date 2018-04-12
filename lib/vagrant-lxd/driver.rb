#
# Copyright (c) 2017-2018 Catalyst.net Ltd
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

require 'active_support/core_ext/object/deep_dup'
require 'hyperkit'
require 'securerandom'
require 'tempfile'
require 'timeout'
require 'vagrant/machine_state'

module VagrantLXD
  class Driver
    include Vagrant::Util

    USER_AGENT = "#{Version::DESCRIPTION} #{Version::VERSION} (#{Hyperkit::Default.user_agent})"

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

    class ContainerAlreadyExists < Vagrant::Errors::VagrantError
      error_key 'lxd_container_already_exists'
    end

    class DuplicateAttachmentFailure < Vagrant::Errors::VagrantError
      error_key 'lxd_duplicate_attachment_failure'
    end

    class SnapshotNotFound < Vagrant::Errors::VagrantError
      error_key 'snapshot_not_found'
    end

    class Hyperkit::BadRequest
      def reason
        return unless data.is_a? Hash

        if error = data[:error]
          return error unless error.empty?
        end

        if metadata = data[:metadata] and err = metadata[:err]
          return err unless err.empty?
        end

        'No reason could be determined'
      end
    end

    NOT_CREATED = Vagrant::MachineState::NOT_CREATED_ID

    attr_reader :api_endpoint
    attr_reader :name
    attr_reader :timeout
    attr_reader :environment
    attr_reader :ephemeral
    attr_reader :nesting
    attr_reader :privileged
    attr_reader :profiles

    def initialize(machine)
      @machine = machine
      @timeout = machine.provider_config.timeout
      @api_endpoint = machine.provider_config.api_endpoint
      @config = @machine.provider_config.config
      @environment = machine.provider_config.environment
      @nesting = machine.provider_config.nesting
      @privileged = machine.provider_config.privileged
      @ephemeral = machine.provider_config.ephemeral
      @profiles = machine.provider_config.profiles
      @name = machine.provider_config.name
      @logger = Log4r::Logger.new('vagrant::lxd')
      @lxd = Hyperkit::Client.new(api_endpoint: api_endpoint.to_s, verify_ssl: false, user_agent: USER_AGENT)
    end

    def validate!
      raise error(ConnectionFailure) unless connection_usable?
      raise error(AuthenticationFailure) unless authentication_usable?
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

    def mounted?(name, options)
      container = @lxd.container(machine_id)
      devices = container[:devices].to_hash
      name = name.to_sym
      begin
        devices[name] and
        devices[name][:type] == 'disk' and
        devices[name][:path] == options[:guestpath] and
        devices[name][:source] == options[:hostpath]
      end
    end

    def unmount(name, options)
      container = @lxd.container(machine_id)
      devices = container[:devices].to_hash
      devices.delete(name.to_sym)
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
      fail ContainerNotFound, machine_name: @machine.name, container: container
    end

    def detach
      @machine.id = nil
    end

    #
    # The following methods correspond directly to middleware actions.
    #

    def snapshot_list
      @lxd.snapshots(machine_id)
    end

    def snapshot_save(name)
      snapshot_delete(name) # noops if the snapshot doesn't exist
      operation = @lxd.create_snapshot(machine_id, name, sync: false)
      wait_for_operation(operation)
    end

    def snapshot_restore(name)
      operation = @lxd.restore_snapshot(machine_id, name, sync: false)
      wait_for_operation(operation)
    rescue Hyperkit::BadRequest
      @logger.warn 'Snapshot restoration failed: ' << name
      fail SnapshotNotFound, machine: @machine.name, snapshot_name: name
    end

    def snapshot_delete(name)
      @lxd.delete_snapshot(machine_id, name)
    rescue Hyperkit::NotFound
      @logger.warn 'No such snapshot: ' << name
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

        container = @lxd.create_container(machine_id, ephemeral: ephemeral, fingerprint: fingerprint, config: config, profiles: profiles)
        @logger.debug 'Created container: ' << container.inspect

        @machine.id = machine_id
      end
    rescue Hyperkit::Error => e
      @lxd.delete_container(id) rescue nil unless container.nil?
      @lxd.delete_image(image[:metadata][:fingerprint]) rescue nil unless image.nil?
      if e.reason =~ /Container '([^']+)' already exists/
        @machine.ui.error e.reason
        fail ContainerAlreadyExists, machine_name: @machine.name, container: $1
      else
        @machine.ui.error "Failed to create container"
        fail ContainerCreationFailure, machine_name: @machine.name, reason: e.reason
      end
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

    def halt(force = false)
      if in_state? :running, :frozen
        @lxd.stop_container(machine_id, timeout: timeout, force: force)
      end
    rescue Hyperkit::BadRequest
      if force
        fail OperationTimeout, time_limit: timeout, operation: 'stop', machine_id: machine_id
      else
        @machine.ui.warn "Container failed to stop within #{timeout} seconds, forcing shutdown..."
        halt(true)
      end
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

  private

    #
    # The remaining methods are just conveniences, not part of the API
    # used by the rest of the plugin.
    #

    def machine_id
      @machine.id
    end

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

    # Hyperkit doesn't handle socket read timeouts even when auto_sync
    # is enabled or setting sync: true. TODO Upstream a better fix than
    # this, so that `wait_for_operation` really does.
    def wait_for_operation(operation)
      @lxd.wait_for_operation(operation.id)
    rescue Faraday::TimeoutError
      retry
    end

    def container
      @lxd.container(machine_id)
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

    def generate_machine_id
      @name || begin
        id = "vagrant-#{File.basename(Dir.pwd)}-#{@machine.name}-#{SecureRandom.hex(8)}"
        id = id.slice(0...63).gsub(/[^a-zA-Z0-9]/, '-')
        id
      end
    end

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
      # NOTE We reuse ActiveSupport for `#deep_dup` here, but if the Hyperkit
      # dependency ever goes away, drop ActiveSupport and use some other
      # method to get a deep copy of the config.
      config = @config.deep_dup

      # Add security settings, if specified. If not, we omit them so
      # they can be configured by one of the container's profiles instead.
      config[:'security.nesting'] = nesting unless nesting.nil?
      config[:'security.privileged'] = privileged unless privileged.nil?

      # Include user-specified environment variables.
      config.merge! Hash[environment.map { |k, v| [:"environment.#{k}", v] }]

      # Set "raw.idmap" if the host's sub{u,g}id configuration allows it.
      # This allows sharing folders via LXD (see synced_folder.rb).
      # If the user has already specified a 'raw.idmap', leave it alone.
      unless config.include?(:'raw.idmap')
        begin
          # Check for root mappings in /etc/sub{uid,gid}.
          %w(uid gid).each do |type|
            id = Process.send(type)
            if File.readlines("/etc/sub#{type}").grep(/^root:#{id}:[1-9]/).any?
              config[:'raw.idmap'] ||= ''
              config[:'raw.idmap'] << "#{type} #{id} #{VAGRANT_UID}\n"
            end
          end
        rescue StandardError => e
          @logger.warn "Cannot read subordinate permissions file: #{e.message}"
        end
      end

      @logger.debug 'Resulting configuration: ' << config.inspect

      config
    end

    # TODO Image handling should be moved into its own class.
    def prepare_image_file
      tmpdir = Dir.mktmpdir

      lxc_dir = @machine.box.directory
      lxc_rootfs = lxc_dir / 'rootfs.tar.gz'
      lxc_fingerprint = Digest::SHA256.file(lxc_rootfs).hexdigest

      lxd_dir = @machine.box.directory / '..' / 'lxd'
      lxd_rootfs = lxd_dir / 'rootfs.tar.gz'
      lxd_metadata = YAML.load(File.read(lxd_dir / 'metadata.yaml')) rescue nil

      if lxd_rootfs.exist? and lxd_metadata.is_a? Hash and lxd_metadata['source_fingerprint'] == lxc_fingerprint
        @machine.ui.info 'Importing LXC image...'
      else
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
