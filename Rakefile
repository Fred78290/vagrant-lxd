require 'rubygems'
require 'bundler/setup'
require 'rspec/core/rake_task'

Bundler::GemHelper.install_tasks

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = '-I. -fd -rspec/common'
  t.verbose = false
end

task :default => :spec
