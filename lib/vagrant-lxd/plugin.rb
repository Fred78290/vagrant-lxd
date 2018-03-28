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

require 'vagrant-lxd/version'

module VagrantLXD
  class Plugin < Vagrant.plugin('2')
    name Version::NAME
    description Version::DESCRIPTION

    provider(:lxd, box_format: 'lxc', priority: 1) do
      require_relative 'provider'
      Provider
    end

    synced_folder(:lxd) do
      require_relative 'synced_folder'
      SyncedFolder
    end

    config(:lxd, :provider) do
      require_relative 'config'
      Config
    end

    command(:lxd) do
      require_relative 'command'
      Command
    end

    provider_capability(:lxd, 'snapshot_list') do
      require_relative 'capability'
      Capability
    end
  end
end
