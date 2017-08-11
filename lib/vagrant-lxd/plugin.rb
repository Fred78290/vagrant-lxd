require 'vagrant-lxd/version'

module VagrantLXD
  class Plugin < Vagrant.plugin('2')
    name Version::NAME
    description Version::DESCRIPTION

    provider(:lxd, box_format: 'lxc', priority: 1, parallel: true) do
      require_relative 'provider'
      Provider
    end

    synced_folder(:lxd) do
      require_relative 'synced_folder'
      SyncedFolder
    end

    command(:lxd) do
      require_relative 'command'
      Command
    end
  end
end
