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

require 'uri'

module VagrantLXD
  class Config < Vagrant.plugin('2', :config)
    attr_accessor :api_endpoint
    attr_accessor :timeout

    def initialize
      @timeout = UNSET_VALUE
      @api_endpoint = UNSET_VALUE
    end

    def validate(machine)
      errors = _detected_errors

      unless api_endpoint == UNSET_VALUE
        begin
          URI(api_endpoint).scheme == 'https' or raise URI::InvalidURIError
        rescue URI::InvalidURIError
          errors << "Invalid `api_endpoint' (value must be a valid HTTPS address): #{api_endpoint.inspect}"
        end
      end

      { Version::NAME => errors }
    end

    def finalize!
      @timeout = timeout.to_i rescue 10

      if api_endpoint == UNSET_VALUE
        @api_endpoint = URI('https://127.0.0.1:8443')
      else
        @api_endpoint = URI(api_endpoint)
      end
    end
  end
end
