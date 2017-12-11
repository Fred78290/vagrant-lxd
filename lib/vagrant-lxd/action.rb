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
      def initialize(app, env, *args)
        @app = app
        @args = args
        @driver = Driver.new(env[:machine])
      end

      def call(env)
        env[:"machine_#{method}"] = @driver.send(method, *@args)
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
    # Check whether the LXD driver is usable and immediately signal an
    # error if not (preventing any remaining middlewares from running).
    #
    class ConnectionValidate
      def initialize(app, env)
        @app = app
        @driver = Driver.new(env[:machine])
      end

      def call(env)
        @driver.validate!
        @app.call(env)
      end
    end

    #
    # Action definitions.
    #
    class << Action
      include Vagrant::Action::Builtin

      def up
        builder do |b|
          b.use Call, state do |env, c|
            case env[:machine_state]
            when Vagrant::MachineState::NOT_CREATED_ID
              c.use Message, :info, 'Machine has not been created yet, starting...'
              c.use HandleBox
              c.use LXD.action(:create)
              c.use LXD.action(:resume)
              c.use SetHostname
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
        builder do |b|
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
        builder do |b|
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
        builder do |b|
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
        builder do |b|
          b.use Call, state do |env, c|
            case env[:machine_state]
            when Vagrant::MachineState::NOT_CREATED_ID
              next
            when :running
              c.use Message, :info, 'Machine is already running.'
            when :frozen, :stopped
              c.use Message, :info, 'Resuming machine...'
              c.use LXD.action(:resume)
              c.use SetHostname
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
        builder do |b|
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
        builder do |b|
          b.use Call, IsState, Vagrant::MachineState::NOT_CREATED_ID do |env, c|
            if env[:result]
              next
            else
              c.use Provision
            end
          end
        end
      end

      def snapshot_list
        builder do |b|
          b.use Call, IsState, Vagrant::MachineState::NOT_CREATED_ID do |env, c|
            if env[:result]
              next
            else
              c.use LXD.action(:snapshot_list)
            end
          end
        end
      end

      def snapshot_save
        builder do |b|
          b.use Call, IsState, Vagrant::MachineState::NOT_CREATED_ID do |env, c|
            if env[:result]
              next
            else
              c.use Message, :info, I18n.t('vagrant.actions.vm.snapshot.saving', name: env[:snapshot_name])
              c.use LXD.action(:snapshot_save), env[:snapshot_name]
              c.use Message, :success, I18n.t('vagrant.actions.vm.snapshot.saved', name: env[:snapshot_name])
            end
          end
        end
      end

      def snapshot_restore
        builder do |b|
          b.use Call, IsState, Vagrant::MachineState::NOT_CREATED_ID do |env, c|
            if env[:result]
              next
            else
              c.use Message, :info, I18n.t('vagrant.actions.vm.snapshot.restoring', name: env[:snapshot_name])
              c.use LXD.action(:snapshot_restore), env[:snapshot_name]
              c.use Message, :success, I18n.t('vagrant.actions.vm.snapshot.restored', name: env[:snapshot_name])
              c.use Call, IsEnvSet, :snapshot_delete do |env, d|
                d.use snapshot_delete if env[:result]
              end
            end
          end
        end
      end

      def snapshot_delete
        builder do |b|
          b.use Call, IsState, Vagrant::MachineState::NOT_CREATED_ID do |env, c|
            if env[:result]
              next
            else
              c.use Message, :info, I18n.t('vagrant.actions.vm.snapshot.deleting', name: env[:snapshot_name])
              c.use LXD.action(:snapshot_delete), env[:snapshot_name]
              c.use Message, :info, I18n.t('vagrant.actions.vm.snapshot.deleted', name: env[:snapshot_name])
            end
          end
        end
      end

      def state
        builder { |b| b.use LXD.action(:state) }
      end

      def info
        builder { |b| b.use LXD.action(:info) }
      end

      def ssh
        builder { |b| b.use SSHExec }
      end

      def ssh_run
        builder { |b| b.use SSHRun }
      end

    private

      def builder
        Vagrant::Action::Builder.new.tap do |b|
          b.use ConfigValidate
          b.use ConnectionValidate
          yield b
        end
      end
    end
  end
end
