require 'hyperkit'
require 'tempfile'
require 'timeout'
require 'vagrant/machine_state'

module VagrantLXD
  class Driver
    include Vagrant::Util

    VAGRANT_UID = 1000

    class OperationTimeout < Vagrant::Errors::VagrantError
      error_key 'lxd_operation_timeout'
    end

    def initialize(machine)
      @machine = machine
      @logger = Log4r::Logger.new('vagrant::lxd')
      @lxd = Hyperkit::Client.new(api_endpoint: 'https://127.0.0.1:8443', verify_ssl: false)
      @lxd.images # basic connectivity test
    rescue Faraday::ConnectionFailed => e
      fail Vagrant::Errors::ProviderNotUsable,
        provider: 'lxd',
        machine: @machine.name,
        message: I18n.t('vagrant.errors.lxd_connection_failure',
          https_address: '127.0.0.1',
          api_endpoint: 'https://127.0.0.1:8443',
          client_cert: File.expand_path('.config/lxc/client.crt', ENV['HOME']))
    end

    def container_name
      "vagrant-#{File.basename(Dir.pwd)}-#{@machine.name}"
    end

    def container
      @lxd.container(container_name)
    end

    def container_image
      @lxd.image_by_alias(container_name)
    end

    def container_state
      @lxd.container_state(container_name)
    end

    def synced_folders_usable?
      # Check whether we've registered an idmap for the current user.
      if map = container[:config][:'raw.idmap']
        true if map =~ /^uid #{Process.uid} #{VAGRANT_UID}$/
      end
    end

    def mount(name, options)
      container = @lxd.container(container_name)
      devices = container[:devices].to_hash
      devices[name] = { type: 'disk', path: options[:guestpath], source: options[:hostpath] }
      container[:devices] = devices
      @lxd.update_container(container_name, container)
    end

    def unmount(name, options)
      container = @lxd.container(container_name)
      devices = container[:devices].to_hash
      devices.delete(:vagrant)
      container[:devices] = devices
      @lxd.update_container(container_name, container)
    end

    def state
      container_state[:status].downcase.to_sym
    rescue Hyperkit::NotFound
      Vagrant::MachineState::NOT_CREATED_ID
    end

    def create
      if in_state? Vagrant::MachineState::NOT_CREATED_ID
        prepare_image(@machine.box) do |path|
          image = @lxd.create_image_from_file(path, alias: container_name)
          image_alias = @lxd.create_image_alias(image[:metadata][:fingerprint], container_name)
          container = @lxd.create_container(container_name, alias: container_name, config: build_config)
          @logger.debug 'Created image: ' << image.inspect
          @logger.debug 'Created container: ' << container.inspect
          @machine.id = container[:id]
        end
      end
    end

    def resume
      case state
      when :stopped
        @lxd.start_container(container_name)
      when :frozen
        @lxd.unfreeze_container(container_name, timeout: 10)
      end
    rescue Hyperkit::BadRequest
      @machine.ui.warn 'Container failed to start within 10 seconds'
      fail OperationTimeout, time_limit: 10, operation: 'start', container_name: container_name
    end

    def halt
      if in_state? :running, :frozen
        @lxd.stop_container(container_name, timeout: 10)
      end
    rescue Hyperkit::BadRequest
      @machine.ui.warn 'Container failed to stop within 10 seconds, forcing shutdown...'
      @lxd.stop_container(container_name, timeout: 10, force: true)
    end

    def suspend
      if in_state? :running
        @lxd.freeze_container(container_name, timeout: 10)
      end
    rescue Hyperkit::BadRequest
      @machine.ui.warn 'Container failed to suspend within 10 seconds'
      fail OperationTimeout, time_limit: 10, operation: 'info', container_name: container_name
    end

    def destroy
      if in_state? :stopped
        @lxd.delete_container(container_name)
        @lxd.delete_image(container_image[:fingerprint])
      else
        @logger.debug "Skipped destroy (#{container_name} is not stopped)"
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

    def in_state?(*any)
      any.include?(state)
    end

    def ipv4_port
      22
    end

    def ipv4_address
      @logger.debug "Looking up ipv4 address for #{container_name}..."
      Timeout.timeout(10) do
        loop do
          if address = container_state[:network][:eth0][:addresses].find { |a| a[:family] == 'inet' }
            return address[:address]
          else
            @logger.debug "No ipv4 address found, sleeping 1s before trying again..."
            sleep(1)
          end
        end
      end
    rescue Timeout::Error
      @logger.warn "Failed to find ipv4 address for #{container_name} within 10 seconds!"
      fail OperationTimeout, time_limit: 10, operation: 'info', container_name: container_name
    end

    def build_config
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

    def prepare_image(box)
      tmpdir = Dir.mktmpdir
      rootfs = box.directory / 'rootfs.tar.gz'

      @machine.ui.info 'Converting LXC image to LXD format...'

      SafeChdir.safe_chdir(tmpdir) do
        FileUtils.cp(rootfs, tmpdir)
        Subprocess.execute('gunzip', 'rootfs.tar.gz')
        File.open('metadata.yaml', 'w') do |metadata|
          metadata.puts 'architecture: x86_64'
          metadata.puts 'creation_date: ' << Time.now.strftime("%s")
        end
        Subprocess.execute('tar', '-rf', 'rootfs.tar', 'metadata.yaml')
        Subprocess.execute('gzip', 'rootfs.tar')
      end

      yield File.join(tmpdir, 'rootfs.tar.gz')
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end
