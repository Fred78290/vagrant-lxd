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

require 'vagrant-lxd/driver'

module VagrantLXD
  class SyncedFolder < Vagrant.plugin('2', :synced_folder)

    def usable?(machine, raise_error = false)
      return false unless machine.provider_name == :lxd

      @driver ||= Driver.new(machine)

      if @driver.synced_folders_usable?
        true
      elsif not raise_error
        false
      else
        fail Vagrant::Errors::SyncedFolderUnusable, type: 'lxd'
      end
    end

    # TODO Figure out the proper way to mount folders before
    # provisioning without using `#prepare` (which is deprecated).
    def prepare(machine, folders, opts)
      enable(machine, folders, opts)
    end

    def enable(machine, folders, opts)
      usable?(machine, true)

      # Skip any folders that are already attached.
      # TODO This could be made less chatty by fetching the whole list
      # of devices up front and comparing the incoming folders to that.
      folders = folders.reject do |name, folder|
        @driver.mounted?(name, folder)
      end

      if folders.any?
        machine.ui.info 'Mounting shared folders...'
        folders.reject { |_, f| f[:disabled] }.each do |name, folder|
          machine.ui.detail "#{folder[:guestpath]} => #{folder[:hostpath]}"
          @driver.mount(name, folder)
        end
      end
    end

    def disable(machine, folders, opts)
      usable?(machine, true)

      if folders.any?
        machine.ui.info 'Unmounting shared folders...'
        folders.reject { |_, f| f[:disabled] }.each do |name, folder|
          machine.ui.detail "#{folder[:guestpath]} => #{folder[:hostpath]}"
          @driver.unmount(name, folder)
        end
      end
    end
  end
end
