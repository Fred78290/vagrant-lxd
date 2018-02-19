require 'lib/vagrant-lxd'
require 'lib/vagrant-lxd/config'
require 'lib/vagrant-lxd/version'

describe VagrantLXD::Config do
  let('t') { double('t') }
  let('machine') { double('machine') }

  let('validation_errors') do
    subject.validate(machine).fetch(VagrantLXD::Version::NAME)
  end

  subject do
    instance = super()
    instance.finalize!
    instance
  end

  context 'with default settings' do
    it('should be valid') { validation_errors.should eq [] }
    its('name') { should be nil }
    its('api_endpoint') { should eq URI("https://127.0.0.1:8443") }
    its('timeout') { should be 10 }
    its('nesting') { should be nil }
    its('privileged') { should be nil }
    its('ephemeral') { should be false }
    its('profiles') { should eq ['default'] }
  end

  context 'with an unrecognised setting' do
    it 'should indicate an error' do
      subject.nonexistent_setting = true
      I18n.should_receive('t').with('vagrant.config.common.bad_field', fields: 'nonexistent_setting').and_return(t)
      validation_errors.should eq [t]
    end
  end

  describe 'the profiles setting' do
    it 'should accept valid values' do
      subject.profiles = ['crayola']
      subject.finalize!
      subject.profiles.should eq ['crayola']
      validation_errors.should eq []
    end

    it 'should reject non-array values' do
      subject.profiles = 36
      subject.finalize!
      validation_errors.should eq ["Invalid `profiles' (value must be an array of strings): 36"]
    end

    it 'should reject invalid profile names' do
      subject.profiles = [36, 'chambers']
      subject.finalize!
      validation_errors.should eq [%{Invalid `profiles' (value must be an array of strings): [36, "chambers"]}]
    end
  end
end
