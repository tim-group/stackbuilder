require 'pp'
require 'yaml'
require 'rubygems'
require 'stacks/environment'
require 'stacks/mcollective/support'
require 'ci/reporter/rspec'
require 'set'
require 'rspec'
require 'compute/controller'

include Rake::DSL
extend Stacks::DSL
require 'stack.rb'

include Stacks::MCollective::Support

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

      desc "outputs the spec format to feed to the compute controller"
      task :to_specs do
        puts machine_def.to_specs.to_yaml
      end

      desc "allocate machines to hosts"
      task :allocate do
        computecontroller = Compute::Controller.new
        pp computecontroller.allocate(machine_def.to_specs)
      end

      desc "resolve IP numbers of launched machines"
      task :resolve do
        computecontroller = Compute::Controller.new
        pp computecontroller.resolve(machine_def.to_specs)
      end

      desc "launch the machines in this bucket"
      task :launch do
        computecontroller = Compute::Controller.new
        computecontroller.launch(machine_def.to_specs)
      end

      desc "mping"
      task :mping do
        machine_def.accept do |machine_def|
          mcollective_fabric :key=>'seed', :broker=> "st-puppetmaster-001.mgmt.st.net.local" do
           pp ping()
          end
        end
      end

      desc "puppet"
      task :puppet do
        machine_def.accept do |machine_def|
          mcollective_fabric :key=>'seed', :broker=> "st-puppetmaster-001.mgmt.st.net.local" do
            puppetroll(machine_def.mgmt_fqdn)
          end
        end
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
