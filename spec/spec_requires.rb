begin
  require 'simplecov'
  SimpleCov.start
rescue Gem::LoadError
  puts "simplecov not installed, not generating coverage reports"
end

# global requires, pulled in before any test has run
require 'allocator/ephemeral_allocator'
require 'allocator/host'
require 'allocator/host_policies'
require 'allocator/host_preference'
require 'allocator/host_repository'
require 'allocator/hosts'
require 'compute/controller'
require 'facter'
require 'matchers/server_matcher'
require 'puppet'
require 'puppet/indirector/node/stacks'
require 'rspec'
require 'securerandom'
require 'set'
require 'stacks/environment'
require 'stacks/factory'
require 'stacks/inventory'
require 'stacks/machine_def'
require 'stacks/namespace'
require 'stacks/test_framework'
require 'support/callback'
require 'support/forking'
require 'support/mcollective'
require 'support/mcollective_puppet'
require 'support/nagios'
require 'support/subscription'
require 'web-test-framework'
