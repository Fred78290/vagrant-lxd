$: << File.expand_path('../lib', __FILE__)

require 'vagrant-lxd/version'

Gem::Specification.new do |spec|
  spec.name          = VagrantLXD::Version::NAME
  spec.version       = VagrantLXD::Version::VERSION
  spec.summary       = VagrantLXD::Version::DESCRIPTION
  spec.authors       = ['Evan Hanson']
  spec.email         = ['evanh@catalyst.net.nz']
  spec.license       = 'GPLv3'
  spec.homepage      = 'https://gitlab.wgtn.cat-it.co.nz/evanh/vagrant-lxd'
  spec.require_paths = ['lib']
  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.add_runtime_dependency 'hyperkit', '~> 1.1.0'
end
