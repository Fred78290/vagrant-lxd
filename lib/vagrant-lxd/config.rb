#
# Copyright (c) 2017-2018 Catalyst.net Ltd
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
    attr_accessor :timeout
    attr_accessor :config
    attr_accessor :devices
    attr_accessor :environment
    attr_accessor :ephemeral
    attr_accessor :nesting
    attr_accessor :privileged
    attr_accessor :profiles

    def initialize
      @name = UNSET_VALUE
      @timeout = UNSET_VALUE
      @config = {}
      @devices = {}
      @environment = UNSET_VALUE
      @nesting = UNSET_VALUE
      @privileged = UNSET_VALUE
      @ephemeral = UNSET_VALUE
      @profiles = UNSET_VALUE
      @api_endpoint = UNSET_VALUE
    end

    def merge(other)
      super.tap do |result|
        c = @config.merge(other.config)
        result.instance_variable_set(:@config, c)
        c = @devices.merge(other.devices)
        result.instance_variable_set(:@devices, c)
      end
    end

    def validate(machine)
      errors = _detected_errors

      unless name.nil?
        if not name.is_a? String
          errors << "Invalid `name' (value must be a string): #{name.inspect}"
        elsif name.size >= 64
          errors << "Invalid `name' (value must be less than 64 characters): #{name.inspect}"
        elsif name =~ /[^a-zA-Z0-9-]/
          errors << "Invalid `name' (value must contain only letters, numbers, and hyphens): #{name.inspect}"
        end
      end

      if not timeout.is_a? Integer
        errors << "Invalid `timeout' (value must be an integer): #{timeout.inspect}"
      elsif timeout < 1
        errors << "Invalid `timeout' (value must be positive): #{timeout.inspect}"
      end

      if not config.is_a? Hash
        errors << "Invalid `config' (value must be a hash): #{config.inspect}"
      elsif not config.keys.all? { |x| x.is_a? Symbol }
        errors << "Invalid `config' (hash keys must be symbols): #{config.inspect}"
      end

      if not devices.is_a? Hash
        errors << "Invalid `devices' (value must be a hash): #{devices.inspect}"
      elsif not devices.keys.all? { |x| x.is_a? Symbol }
        errors << "Invalid `devices' (hash keys must be symbols): #{devices.inspect}"
      end

      if not environment.is_a? Hash
        errors << "Invalid `environment' (value must be a hash): #{environment.inspect}"
      elsif not environment.keys.all? { |x| x.is_a? String or x.is_a? Symbol }
        errors << "Invalid `environment' (hash keys must be strings or symbols): #{environment.inspect}"
      elsif not environment.values.all? { |x| x.is_a? String }
        errors << "Invalid `environment' (hash values must be strings): #{environment.inspect}"
      end

      begin
        URI(api_endpoint).scheme == 'https' or raise URI::InvalidURIError
      rescue URI::InvalidURIError
        errors << "Invalid `api_endpoint' (value must be a valid HTTPS address): #{api_endpoint.inspect}"
      end

      unless [true, false, nil].include? nesting
        errors << "Invalid `nesting' (value must be true or false): #{nesting.inspect}"
      end

      unless [true, false, nil].include? privileged
        errors << "Invalid `privileged' (value must be true or false): #{privileged.inspect}"
      end

      unless [true, false].include? ephemeral
        errors << "Invalid `ephemeral' (value must be true or false): #{ephemeral.inspect}"
      end

      unless profiles.is_a? Array and profiles == profiles.grep(String)
        errors << "Invalid `profiles' (value must be an array of strings): #{profiles.inspect}"
      end

      { Version::NAME => errors }
    end

    def finalize!
      if name == UNSET_VALUE
        @name = nil
      end

      if config == UNSET_VALUE
        @config = {}
      end

      if devices == UNSET_VALUE
        @devices = {}
      end

      if environment == UNSET_VALUE
        @environment = {}
      end

      if nesting == UNSET_VALUE
        @nesting = nil
      end

      if privileged == UNSET_VALUE
        @privileged = nil
      end

      if ephemeral == UNSET_VALUE
        @ephemeral = false
      end

      if profiles == UNSET_VALUE
        @profiles = ['default']
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
