require 'pp'
require 'yaml'
require 'rubygems'
require 'stacks/environment'
require 'stacks/mcollective/support'
require 'ci/reporter/rspec'
require 'set'

include Rake::DSL
extend Stacks::DSL
require 'stack.rb'

environment_name = ENV.fetch('env', 'dev')
bind_to(environment_name)

namespace :sbx do
  accept do |machine_def|
    namespace machine_def.name.to_sym do
      desc "launch the machines in this bucket"
      task :launch do
        puts "launching #{machine_def.name} in environment #{environment_name}\n"
        pp machine_def.machines
      end
    end
  end
end

