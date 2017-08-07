require 'vagrant/action/builder'
require 'vagrant/machine_state'
require 'vagrant-lxd/driver'

module VagrantLXD
  module Action
    include Vagrant::Action::Builtin

    #
    # The DriverProxy class is middleware that simply forwards its call
    # to the corresponding method on the LXD driver and copies the
    # result into the env hash under the key "machine_<method>".
    #
    # The method to be called is controlled by the proxy object's class
    # name.
    #
    class DriverProxy
      def initialize(app, env)
        @app = app
        @driver = Driver.new(env)
      end

      def call(env)
        env[:"machine_#{method}"] = @driver.send(method)
        @app.call(env)
      end

    private

      def method
        self.class.to_s.split('::').last.downcase
      end
    end

    def Action.up
      Vagrant::Action::Builder.new.tap do |b|
        b.use ConfigValidate
        b.use Call, IsState, Vagrant::MachineState::NOT_CREATED_ID do |env, c|
          if env[:result]
            env[:ui].info "Machine '#{env[:machine].name}' has not been created yet, starting..."
            c.use HandleBox
            c.use start
          else
            c.use resume
          end
        end
      end
    end

    %w(destroy halt info resume start state suspend reload resume).each do |name|
      Action.define_singleton_method(name) do
        Vagrant::Action::Builder.new.tap do |b|
          const = name.sub(/[a-z]/, &:upcase)
          proxy = const_get(const) rescue nil

          if proxy.nil?
            proxy = Class.new(DriverProxy)
            const_set(const, proxy)
          end

          b.use ConfigValidate
          b.use proxy
        end
      end
    end

    def Action.ssh
      Vagrant::Action::Builder.new.tap do |b|
        b.use ConfigValidate
        b.use Call, IsState, :running do |env, c|
          c.use SSHExec if env[:result]
        end
      end
    end
  end
end
