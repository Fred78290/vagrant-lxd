require 'vagrant-lxd/driver'

module VagrantLXD
  class SyncedFolder < Vagrant.plugin('2', :synced_folder)

    def usable?(machine, raise_error=false)
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
      usable?(machine, true)
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
