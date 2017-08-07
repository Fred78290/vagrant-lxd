require 'hyperkit'
require 'tempfile'
require 'vagrant/machine_state'

module VagrantLXD
  class Driver
    include Vagrant::Util

    class OperationTimeout < Vagrant::Errors::VagrantError
      error_key 'lxd_operation_timeout'
    end

    def initialize(env)
      @env = env
      @machine = env[:machine]
      @logger = Log4r::Logger.new('vagrant::lxd::driver')
      @lxd = Hyperkit::Client.new(api_endpoint: 'https://127.0.0.1:8443', verify_ssl: false)
      @lxd.images
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

    def state
      state = @lxd.container_state(container_name)
      state[:status].downcase.to_sym
    rescue Hyperkit::NotFound
      Vagrant::MachineState::NOT_CREATED_ID
    end

    def start
      if state == Vagrant::MachineState::NOT_CREATED_ID
        prepare_image(@machine.box) do |path|
          image = @lxd.create_image_from_file(path)
          @logger.debug 'Created image: ' << image.inspect
          container = @lxd.create_container(container_name, fingerprint: image[:metadata][:fingerprint])
          @logger.debug 'Created container: ' << container.inspect
          @machine.id = container[:id]
        end
      end

      resume
    end

    def resume
      case state
      when :stopped
        @lxd.start_container(container_name)
      when :frozen
        @lxd.unfreeze_container(container_name, timeout: 10)
      end
    rescue Hyperkit::BadRequest
      @env[:ui].warn 'Container failed to start within 10 seconds'
      fail OperationTimeout, time_limit: 10, operation: 'start', container_name: container_name
    end

    def halt
      if in_state? :running, :frozen
        @lxd.stop_container(container_name, timeout: 10)
      end
    rescue Hyperkit::BadRequest
      @env[:ui].warn 'Container failed to stop within 10 seconds, forcing shutdown...'
      @lxd.stop_container(container_name, timeout: 10, force: true)
    end

    def destroy
      halt

      unless in_state? Vagrant::MachineState::NOT_CREATED_ID
        @lxd.delete_container(container_name)
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

    def reload
      halt
      resume
    end

    def suspend
      if in_state? :running
        @lxd.freeze_container(container_name, timeout: 10)
      end
    rescue Hyperkit::BadRequest
      @env[:ui].warn 'Container failed to suspend within 10 seconds'
      fail OperationTimeout, time_limit: 10, operation: 'info', container_name: container_name
    end

  private

    def in_state?(*any)
      any.include?(state)
    end

    def ipv4_port
      22
    end

    def ipv4_address
      state = @lxd.container_state(container_name)
      state[:network][:eth0][:addresses].find do |address|
        return address[:address] if address[:family] == 'inet'
      end
    end

    def prepare_image(box)
      tmpdir = Dir.mktmpdir
      rootfs = box.directory / 'rootfs.tar.gz'

      @env[:ui].info 'Converting LXC image to LXD format...'

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
