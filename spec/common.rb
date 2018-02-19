require 'vagrant'
require 'rspec/its'
require 'rspec/mocks'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = [:should, :expect] }
  config.mock_with(:rspec) { |c| c.syntax = [:should, :expect] }
end
