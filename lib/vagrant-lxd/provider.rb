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

require 'vagrant-lxd/action'

module VagrantLXD
  class Provider < Vagrant.plugin('2', :provider)
    def initialize(machine)
      @machine = machine
    end

    def action(name)
      Action.send(name) if Action.respond_to?(name)
    end

    def state
      env = @machine.action('state', lock: false)
      state = env[:machine_state]
      short = state.to_s.gsub('_', ' ')
      long = I18n.t("vagrant.commands.status.#{state}")
      Vagrant::MachineState.new(state, short, long)
    end

    def ssh_info
      env = @machine.action('info', lock: false)
      env[:machine_info]
    end

    def to_s
      'LXD'
    end
  end
end
