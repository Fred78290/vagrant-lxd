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

$: << File.expand_path('../lib', __FILE__)

require 'vagrant-lxd/version'

Gem::Specification.new do |spec|
  spec.name          = VagrantLXD::Version::NAME
  spec.version       = VagrantLXD::Version::VERSION
  spec.summary       = VagrantLXD::Version::DESCRIPTION
  spec.description   = 'A Vagrant plugin that allows management of containers using LXD.'
  spec.authors       = ['Evan Hanson']
  spec.email         = ['evanh@catalyst.net.nz']
  spec.license       = 'GPL-3.0'
  spec.homepage      = 'https://gitlab.com/catalyst-it/vagrant-lxd'
  spec.require_paths = ['lib']
  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.add_runtime_dependency 'hyperkit', '~> 1.1.0'
end
