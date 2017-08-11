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

module VagrantLXD
  class Config < Vagrant.plugin('2', :config)
    attr_accessor :timeout

    def initialize
      @timeout = UNSET_VALUE
    end

    def finalize!
      @timeout = timeout.to_i rescue 10
    end
  end
end
