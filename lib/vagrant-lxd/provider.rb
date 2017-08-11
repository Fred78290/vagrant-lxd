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
