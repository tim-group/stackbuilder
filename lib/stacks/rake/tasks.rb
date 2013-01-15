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
ENV['CI_REPORTS'] = 'build/spec/reports/'

namespace :sbx do
  accept do |machine_def|
    namespace machine_def.name.to_sym do
      RSpec::Core::Runner.disable_autorun!
      desc "launch the machines in this bucket"
      task :launch do
        pp machine_def.machines
      end

      desc "test"
      task :test do
        machine_def.accept do |machine_def|
          specpath = File.dirname(__FILE__) + "/../stacktests/#{machine_def.clazz}/*.rb"
          describe "#{machine_def.clazz}.#{machine_def.name}" do
            Dir[specpath].each do |file|
              require file
              test = File.basename(file, '.rb')
              it_behaves_like test, machine_def
            end
          end
        end
        RSpec::Core::Runner.run(['--format','CI::Reporter::RSpec'],$stderr,$stdout)
      end
    end
  end
end
