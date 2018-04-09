require 'lib/vagrant-lxd'
require 'lib/vagrant-lxd/action'
require 'lib/vagrant-lxd/driver'

describe VagrantLXD::Driver do
  let(:lxd) { double('lxd') }
  let(:machine) { double('machine').as_null_object }

  before do
    Hyperkit::Client.stub(:new).and_return(lxd)
  end

  subject do
    described_class.new(machine)
  end

  context 'before the machine has been created' do
    before do
      machine.stub(:id).and_return(nil)
    end

    its('state') { should be Vagrant::MachineState::NOT_CREATED_ID }
    its('info') { should be nil }
  end

  context 'with a running machine' do
    let(:container_name) { 'example' }
    let(:container_status) { 'Running' }
    let(:container_address) { '10.0.8.211' }

    let(:container) do
      {
        name: container_name,
        status: container_status,
        stateful: false,
        ephemeral: false,
        profiles: ['default'],
        devices: { root: { path: '/', type: 'disk' } },
      }
    end

    let(:container_state) do
      {
        pid: Process.pid,
        status: container_status,
        network: {
          eth0: {
            addresses: [{
              family: 'inet',
              address: container_address,
              netmask: '24',
              scope: 'global',
            }]
          }
        }
      }
    end

    before do
      machine.stub(:id).and_return(container_name)
      lxd.stub(:container).and_return(container)
      lxd.stub(:container_state).and_return(container_state)
    end

    its('state') { should be :running }

    describe 'info' do
      it 'should have a host and port' do
        info = subject.info
        info.should be_a Hash
        info[:host].should eq container_address
        info[:port].should eq 22
      end
    end
  end
end
