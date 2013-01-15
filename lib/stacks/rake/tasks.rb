require 'pp'
require 'yaml'
require 'rubygems'
require 'stacks/environment'
require 'stacks/mcollective/support'
require 'ci/reporter/rspec'
require 'set'
require 'rspec'

include Rake::DSL
extend Stacks::DSL
require 'stack.rb'

environment_name = ENV.fetch('env', 'dev')
bind_to(environment_name)

RSpec::Core::Runner.disable_autorun!
config = RSpec.configuration
config.color_enabled = true

namespace :sbx do
  accept do |machine_def|
    namespace machine_def.name.to_sym do
      RSpec::Core::Runner.disable_autorun!
      desc "launch the machines in this bucket"
      task :launch do
        pp machine_def.machines
      end
    end
  end

  # we should fuse this loop with the above one - one call to accept
  # should move the test definition code out into a method to make that clean
  # just leave the task blocks in the loop
  accept do |machine_def|
    namespace machine_def.name.to_sym do
      desc "test"
      task :test do
        machine_def.accept do |machine_def|
          specpath = File.dirname(__FILE__) + "/../stacktests/#{machine_def.clazz}/*.rb"

          describe "#{machine_def.clazz}.#{machine_def.name}" do
            Dir[specpath].each do |file|
              require file
              puts "required " + file
              test = File.basename(file, '.rb')
              it_behaves_like test, machine_def
              puts "for #{machine_def.name} added #{test}"
            end
          end
        end
        RSpec::Core::Runner.run(['--format','CI::Reporter::RSpec'],$stderr,$stdout)
      end
    end

    def self.extended(object)
      self.children.each do |child|
        child.define_rspec
      end
      tests = self.rspecs
    end
  end
end
