require 'vagrant-lxd/version'

module VagrantLXD
  class Command < Vagrant.plugin('2', :command)
    def execute
      @env.ui.info "Vagrant LXD Provider"
      @env.ui.info "Version #{Version::VERSION}"
    end
  end
end
