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

require 'vagrant/machine_state'

require 'vagrant-lxd/driver'
require 'vagrant-lxd/version'

module VagrantLXD
  class Command < Vagrant.plugin('2', :command)
    def Command.synopsis
      'manages the LXD provider'
    end

    def execute
      main, subcommand, args = split_main_and_subcommand(@argv)

      opts = OptionParser.new do |o|
        o.banner = 'Usage: vagrant lxd <command>'
        o.separator ''
        o.separator 'Commands:'
        o.separator '     attach    associate machine with a running container'
        o.separator '     detach    disassociate machine from a running container'
        o.separator '     version   print current plugin version'
        o.separator ''
        o.separator 'For help on a specific command, run `vagrant lxd <command> -h`'
      end

      if main.include?('-h') or main.include?('--help')
        @env.ui.info opts.help
        exit 0
      end

      case subcommand
      when 'attach'
        attach(args)
      when 'detach'
        detach(args)
      when 'version'
        @env.ui.info 'Vagrant LXD Provider'
        @env.ui.info 'Version ' << Version::VERSION
      else
        fail Vagrant::Errors::CLIInvalidUsage, help: opts.help
      end
    end

    def attach(args)
      options = Hash[force: false]

      opts = OptionParser.new do |o|
        o.banner = 'Usage: vagrant lxd attach [-f] [machine ... container]'
        o.separator ''
        o.separator 'Associates a VM with a preexisting LXD container.'
        o.separator ''
        o.separator 'This command can be used to attach an inactive (not created) VM to a'
        o.separator 'preexisting LXD container. Once it has been associated with a container,'
        o.separator 'the machine can be used just like it had been created with `vagrant up`'
        o.separator 'or detached from the container again with `vagrant lxd detach`.'
        o.separator ''
        o.on('-f', '--force', 'Force attachment and ignore missing containers')
      end

      if args.include?('-h') or args.include?('--help')
        @env.ui.info opts.help
        exit 0
      end

      options[:force] ||= args.delete('-f')
      options[:force] ||= args.delete('--force')
      options[:container_name] = args.pop

      with_target_machines(args) do |machine|
        if not container = options[:container_name] || machine.provider_config.name
          machine.ui.warn 'No container name specified, skipping...'
        elsif machine.id == container
          machine.ui.warn "Machine is already attached to container '#{container}', skipping..."
        elsif machine.state.id == Vagrant::MachineState::NOT_CREATED_ID
          machine.ui.info "Attaching to container '#{container}'..."
          begin
            Driver.new(machine).attach(container)
          rescue Driver::ContainerNotFound
            raise unless options[:force]
          end
        elsif options[:force]
          detach([machine.name])
          redo
        else
          machine.ui.error "Machine is already attached to container '#{machine.id}'"
          fail Driver::DuplicateAttachmentFailure, machine_name: machine.name, container: container
        end
      end
    end

    def detach(args)
      opts = OptionParser.new do |o|
        o.banner = 'Usage: vagrant lxd detach [machine ...]'
        o.separator ''
        o.separator 'Disassociates a VM from its LXD container.'
        o.separator ''
        o.separator 'This command can be used to deactivate a VM without destroying the'
        o.separator 'underlying container. Once detached, the machine can be recreated'
        o.separator 'from scratch with `vagrant up` or associated to a different container'
        o.separator 'by using `vagrant lxd attach`.'
      end

      if args.include?('-h') or args.include?('--help')
        @env.ui.info opts.help
        exit 0
      end

      with_target_machines(args) do |machine|
        if machine.id.nil? or machine.state.id == Vagrant::MachineState::NOT_CREATED_ID
          machine.ui.warn "Machine is not attached to a container, skipping..."
        else
          machine.ui.info "Detaching from container '#{machine.id}'..."
          Driver.new(machine).detach
        end
      end
    end

    def with_target_machines(args)
      machines = args.map(&:to_sym)

      # NOTE We collect all vm names here in order to force Vagrant to
      # load a full local environment, including provider configurations.
      vms = with_target_vms { |_| }.map(&:name)

      # When no machines are given, act on all of them.
      machines = vms if machines.empty?

      # Validate machine names.
      unless vms | machines == vms
        fail Vagrant::Errors::MachineNotFound, name: (machines - vms).first
      end

      machines.each do |name|
        yield @env.machine(name, :lxd)
      end
    end
  end
end
