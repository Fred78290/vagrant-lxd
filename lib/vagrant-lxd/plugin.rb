require 'vagrant-lxd/version'

module VagrantLXD
  class Plugin < Vagrant.plugin('2')
    name Version::NAME
    description Version::DESCRIPTION

    provider(:lxd, box_format: 'lxc', priority: 0) do
      require_relative 'provider'
      Provider
    end

    command(:lxd) do
      require_relative 'command'
      Command
    end
  end
end
