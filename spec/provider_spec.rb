require 'lib/vagrant-lxd'
require 'lib/vagrant-lxd/action'
require 'lib/vagrant-lxd/provider'

describe VagrantLXD::Provider do
  let(:t) { double('t') }
  let(:machine) { double('machine') }
  let(:machine_info) { Hash(host: '127.0.0.1', port: 22) }
  let(:machine_state) { Vagrant::MachineState::NOT_CREATED_ID }

  subject do
    described_class.new(machine)
  end

  describe 'ssh_info' do
    it 'should return machine info' do
      machine.should_receive(:action).with('info', any_args).and_return(machine_info: machine_info)
      subject.ssh_info.should == machine_info
    end
  end

  describe 'state' do
    it 'should return the machine state' do
      machine.should_receive(:action).with('state', any_args).and_return(machine_state: machine_state)
      I18n.should_receive('t').with('vagrant.commands.status.not_created').and_return(t)
      result = subject.state
      result.should be_a Vagrant::MachineState
      result.id.should be Vagrant::MachineState::NOT_CREATED_ID
      result.short_description.should == 'not created'
      result.long_description.should == t
    end
  end
end
