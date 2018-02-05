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
    attr_accessor :name
    attr_accessor :ephemeral
    attr_accessor :timeout

    def initialize
      @name = UNSET_VALUE
      @timeout = UNSET_VALUE
      @ephemeral = UNSET_VALUE
      @api_endpoint = UNSET_VALUE
    end

    def validate(machine)
      errors = _detected_errors

      unless [UNSET_VALUE, nil].include? name
        if not name.is_a? String
          errors << "Invalid `name' (value must be a string): #{name.inspect}"
        elsif name.size >= 64
          errors << "Invalid `name' (value must be less than 64 characters): #{name.inspect}"
        elsif name =~ /[^a-zA-Z0-9-]/
          errors << "Invalid `name' (value must contain only letters, numbers, and hyphens): #{name.inspect}"
        end
      end

      unless timeout == UNSET_VALUE
        if not timeout.is_a? Integer
          errors << "Invalid `timeout' (value must be an integer): #{timeout.inspect}"
        elsif timeout < 1
          errors << "Invalid `timeout' (value must be positive): #{timeout.inspect}"
        end
      end

      unless api_endpoint == UNSET_VALUE
        begin
          URI(api_endpoint).scheme == 'https' or raise URI::InvalidURIError
        rescue URI::InvalidURIError
          errors << "Invalid `api_endpoint' (value must be a valid HTTPS address): #{api_endpoint.inspect}"
        end
      end

      unless [UNSET_VALUE, true, false].include? ephemeral
        errors << "Invalid `ephemeral' (value must be true or false): #{ephemeral.inspect}"
      end

      { Version::NAME => errors }
    end

    def finalize!
      if name == UNSET_VALUE
        @name = nil
      end

      if ephemeral == UNSET_VALUE
        @ephemeral = false
      end

      if timeout == UNSET_VALUE
        @timeout = 10
      end

      if api_endpoint == UNSET_VALUE
        @api_endpoint = URI('https://127.0.0.1:8443')
      else
        @api_endpoint = URI(api_endpoint)
      end
    end
  end
end
