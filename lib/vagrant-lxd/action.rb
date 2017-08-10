require 'vagrant/action/builder'
require 'vagrant/machine_state'
require 'vagrant-lxd/driver'

module VagrantLXD
  module Action

    #
    # The LXD class is middleware that simply forwards its call to the
    # corresponding method on the LXD driver and copies the result into
    # the env hash under the key `:machine_<method>`.
    #
    # The method to be called is controlled by the proxy object's class
    # name. The correct instance to use for a particular method call is
    # retrieved with `LXD.action`.
    #
    class LXD
      def initialize(app, env)
        @app = app
        @driver = Driver.new(env[:machine])
      end

      def call(env)
        env[:"machine_#{method}"] = @driver.send(method)
        @app.call(env)
      end

    private

      def method
        self.class.to_s.split('::').last.downcase
      end

      def LXD.action(name)
        const = name.to_s.sub(/[a-z]/, &:upcase)
        const_get(const)
      rescue NameError
        Class.new(LXD).tap do |proxy|
          const_set(const, proxy)
        end
      end
    end

    #
    # Message issues a message to the user through the `env[:ui]` object
    # provided to this middleware. The level is controlled via `type`,
    # which should be a method on `env[:ui]`.
    #
    class Message
      def initialize(app, env, type, message)
        @app = app
        @type = type
        @message = message
      end

      def call(env)
        env[:ui].send(@type, @message)
        @app.call(env)
      end
    end

    #
    # Action definitions.
    #
    class << Action
      include Vagrant::Action::Builtin

      def up
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, state do |env, c|
            case env[:machine_state]
            when Vagrant::MachineState::NOT_CREATED_ID
              c.use Message, :info, 'Machine has not been created yet, starting...'
              c.use HandleBox
              c.use LXD.action(:create)
              c.use LXD.action(:resume)
              c.use SyncedFolders
              c.use WaitForCommunicator
              c.use Provision
            when :running
              c.use Message, :info, 'Machine is already running.'
            when :frozen, :stopped
              c.use resume
            else
              c.use Message, :error, "Machine cannot be started while #{env[:machine_state]}."
            end
          end
        end
      end

      def destroy
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, IsState, Vagrant::MachineState::NOT_CREATED_ID do |env, c|
            if env[:result]
              next
            else
              c.use Call, DestroyConfirm do |env, d|
                if env[:result]
                  d.use halt
                  d.use Message, :info, 'Destroying machine and associated data...'
                  d.use LXD.action(:destroy)
                else
                  d.use Message, :info, 'Machine will not be destroyed.'
                end
              end
            end
          end
        end
      end

      def halt
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, state do |env, c|
            case env[:machine_state]
            when Vagrant::MachineState::NOT_CREATED_ID
              next
            when :stopped
              c.use Message, :info, 'Machine is already stopped.'
            when :frozen, :running
              c.use Message, :info, 'Stopping machine...'
              c.use LXD.action(:halt)
            else
              c.use Message, :error, "Machine cannot be stopped while #{env[:machine_state]}."
            end
          end
        end
      end

      def suspend
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, state do |env, c|
            case env[:machine_state]
            when Vagrant::MachineState::NOT_CREATED_ID
              next
            when :frozen
              c.use Message, :info, 'Machine is already suspended.'
            when :running
              c.use Message, :info, 'Suspending machine...'
              c.use LXD.action(:suspend)
            else
              c.use Message, :error, "Machine cannot be suspended while #{env[:machine_state]}."
            end
          end
        end
      end

      def resume
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, state do |env, c|
            case env[:machine_state]
            when Vagrant::MachineState::NOT_CREATED_ID
              next
            when :running
              c.use Message, :info, 'Machine is already running.'
            when :frozen, :stopped
              c.use Message, :info, 'Resuming machine...'
              c.use LXD.action(:resume)
              c.use SyncedFolders
              c.use WaitForCommunicator
              c.use Provision
            else
              c.use Message, :error, "Machine cannot be resumed while #{env[:machine_state]}."
            end
          end
        end
      end

      def reload
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use Call, state do |env, c|
            case env[:machine_state]
            when Vagrant::MachineState::NOT_CREATED_ID
              next
            when :frozen, :running
              c.use halt
            end
            c.use resume
          end
        end
      end

      def provision
        Vagrant::Action::Builder.new do |b|
          b.use ConfigValidate
          b.use Call, IsState, Vagrant::MachineState::NOT_CREATED_ID do |env, c|
            if env[:result]
              next
            else
              c.use Provision
            end
          end
        end
      end

      def state
        Vagrant::Action::Builder.build LXD.action(:state)
      end

      def info
        Vagrant::Action::Builder.build LXD.action(:info)
      end

      def ssh
        Vagrant::Action::Builder.build SSHExec
      end

      def ssh_run
        Vagrant::Action::Builder.build SSHRun
      end
    end
  end
end
