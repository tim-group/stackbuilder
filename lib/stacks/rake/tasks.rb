require 'rake'
require 'pp'
require 'yaml'
require 'rubygems'
require 'stacks/environment'
require 'support/mcollective'
require 'ci/reporter/rspec'
require 'set'
require 'rspec'
require 'compute/controller'

include Rake::DSL

include Support::MCollective

extend Stacks::DSL
begin
  require 'stack.rb'
rescue Exception
  puts "Cannot find stack.rb in the local directory, giving up"
  exit 1
end

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

      desc "outputs the specs for these machines, in the format to feed to the provisioning tools"
      task :to_specs do
        puts machine_def.to_specs.to_yaml
      end

      desc "allocate these machines to hosts (but don't actually launch them - this is a dry run)"
      task :allocate do
        computecontroller = Compute::Controller.new
        pp computecontroller.allocate(machine_def.to_specs)
      end

      desc "resolve the IP numbers of these machines"
      task :resolve do
        computecontroller = Compute::Controller.new
        pp computecontroller.resolve(machine_def.to_specs)
      end

      desc "launch these machines"
      task :launch do
        computecontroller = Compute::Controller.new
        pp computecontroller.launch(machine_def.to_specs)
      end

      desc "perform an MCollective ping against these machines"
      task :mping do
        hosts = []
        machine_def.accept do |machine_def| hosts << machine_def.mgmt_fqdn end
        found = false
        5.times do
          found = mco_client("rpcutil", :key => "seed") do |mco|
            hosts.to_set.subset?(mco.discover.to_set)
          end

          break if found
        end

        fail("nodes #{hosts} not checked in to mcollective") unless found
        pp "all nodes found in mcollective #{found}"
      end

      desc "clean Puppet certificates for these machines"
      task :puppet_clean do
        machine_def.accept do |machine_def|
          mco_client("puppetca") do |mco|
            pp mco.clean(:certname => machine_def.mgmt_fqdn)
          end
        end
      end

      desc "sign outstanding Puppet certificate signing requests for these machines"
      task :puppet_sign do
        machine_def.accept do |machine_def|
          mco_client("puppetca") do |mco|
            pp mco.sign(:certname => machine_def.mgmt_fqdn)
          end
        end
      end

      desc "run Puppet on these machines"
      task :puppet do
        hosts = []
        machine_def.accept do |machine_def|
          hosts << machine_def.mgmt_fqdn
        end
        pp hosts
        mco_client("puppetd", :key => "seed") do |mco|
          engine = PuppetRoll::Engine.new({:concurrency => 5}, [], hosts, PuppetRoll::Client.new(hosts, mco))
          engine.execute()
          pp engine.get_report()
        end
      end

      desc "clean away all traces of these machines"
      task :clean do
        computecontroller = Compute::Controller.new
        pp computecontroller.clean(machine_def.to_specs)

        include Support::MCollective
        machine_def.accept do |machine_def|
          if machine_def.respond_to?(:mgmt_fqdn) # only clean things with names, ie servers
            mco_client("puppetca") do |mco|
              pp mco.clean(:certname => machine_def.mgmt_fqdn)
            end
          end
        end
      end

      desc "carry out all appropriate tests on these machines"
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
        RSpec::Core::Runner.run(['--format', 'CI::Reporter::RSpec'], $stderr, $stdout)
      end
    end
  end
end
