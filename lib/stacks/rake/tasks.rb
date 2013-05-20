$: << File.join(File.dirname(__FILE__), "..", "lib")
$: << '/opt/orctool/lib'
require 'orc/util/option_parser'
require 'rake'
require 'pp'
require 'yaml'
require 'rubygems'
require 'stacks/environment'
require 'stacks/inventory'
require 'support/mcollective'
require 'support/mcollective_puppet'
require 'set' # ci/reporter/rspec should require this but doesn't
require 'ci/reporter/rspec'
require 'set'
require 'rspec'
require 'compute/controller'
require 'support/logger'
include Rake::DSL
include Support::MCollective

inventory = Stacks::Inventory.new('.')
environment_name = ENV.fetch('env', 'dev')
environment = inventory.find_environment(environment_name)

RSpec::Core::Runner.disable_autorun!
config = RSpec.configuration
config.color_enabled = true
ENV['CI_REPORTS'] = 'build/spec/reports/'

####
# TODO:
# general:
#         use logging
#         push stuff back out of here
#         does it complain well when keys aren't to be found anywhere?
#           probably want to have a different key in each dc?
#
# possibly:
#         implement visitor pattern to traverse tree
#
# allocate: tidy up output
#
# launch: tidy up output
#         clearly indicate success or failure to launnch
#         launch in parallel
#
# clean machines:
#         clean needs to show what it actually cleaned, currently dumps results
#         need to account for which host each machine was cleaned from
#
# mping:
#         tidy, test and
#
# puppetclean:
#       warn if cert clean did not occur
#       show positive clean action clearly in log
#
# puppetsign:
#       warn if signing did not occur
#       use output more wisely
#       show positive sign action clearly in log
#
# need workflow tasks to tie builds together.
#   ie provision dependson [launch, mping, puppet, test]
#      clean     dependson [destroy_vms, clean_certs]
#

def sbtask(name, &block)
  task name do |task|
    logger.start task.name
    begin
      block.call()
    rescue Exception => e
      logger.failed(name)
      raise e
    end
    logger.passed(name)
  end
end

def do_ip_allocations(type, specs)
  method = "#{type}_ips".to_sym
  computecontroller = Compute::Controller.new
  computecontroller.send(method, specs) do
    on :success do |vm, msg|
      logger.info "#{vm} #{type} IP successfully"
    end
    on :failure do |vm, msg|
      logger.error "#{vm} failed to #{type} IP: #{msg}"
    end
    on :unaccounted do |vm|
      logger.error "#{vm} was unaccounted for"
    end
    has :failure do
      fail "some machines failed to #{type} IPs"
    end
  end
end

namespace :sbx do
  environment.accept do |machine_def|
    namespace machine_def.name.to_sym do
      RSpec::Core::Runner.disable_autorun!

      desc "outputs the specs for these machines, in the format to feed to the provisioning tools"
      task :to_specs do
        puts machine_def.to_specs.to_yaml
      end

      desc "outputs the specs for these machines, in the format to feed to the provisioning tools"
      task :to_vip_spec do
        puts machine_def.to_vip_spec.to_yaml
      end

      if machine_def.respond_to? :to_enc
        desc "outputs the specs for these machines, in the format to feed to the provisioning tools"
        task :to_enc do
          puts machine_def.to_enc.to_yaml
        end
      end

      task :provision=> ['allocate_vips', 'launch', 'puppet:sign', 'puppet:wait', 'orc:resolve']

      desc "allocate these machines to hosts (but don't actually launch them - this is a dry run)"
      sbtask :allocate do
        computecontroller = Compute::Controller.new
        pp computecontroller.allocate(machine_def.to_specs)
      end

      desc "resolve the IP numbers of these machines"
      sbtask :resolve do
        computecontroller = Compute::Controller.new
        pp computecontroller.resolve(machine_def.to_specs)
      end

      desc "disable notify for these machines"
      sbtask :disable_notify do
        computecontroller = Compute::Controller.new
        computecontroller.disable_notify(machine_def.to_specs)
      end

      desc "enable notify for these machines"
      sbtask :enable_notify do
        computecontroller = Compute::Controller.new
        computecontroller.enable_notify(machine_def.to_specs)
      end

      desc "launch these machines"
      sbtask :launch do
        computecontroller = Compute::Controller.new
        computecontroller.launch(machine_def.to_specs) do
          on :allocated do |vm, host|
            logger.info "#{vm} allocated to #{host}"
          end
          on :success do |vm, msg|
            logger.info "#{vm} launched successfully"
          end
          on :failure do |vm, msg|
            logger.error "#{vm} failed to launch: #{msg}"
          end
          on :unaccounted do |vm|
            logger.error "#{vm} was unaccounted for"
          end
          has :failure do
            fail "some machines failed to launch"
          end
        end
      end

      desc "allocate IPs for these virtual services"
      sbtask :allocate_vips do
        vips = []
        machine_def.accept do |child_machine_def|
          vips << child_machine_def.to_vip_spec if child_machine_def.respond_to?(:to_vip_spec)
        end

        do_ip_allocations('allocate', vips)
      end

      desc "free IPs for these virtual services"
      sbtask :free_vips do
        vips = []
        machine_def.accept do |child_machine_def|
          vips << child_machine_def.to_vip_spec if child_machine_def.respond_to?(:to_vip_spec)
        end

        do_ip_allocations('free', vips)
      end

      desc "free IPs"
      sbtask :free_ips do
        all_specs = machine_def.flatten.map { |m| m.to_spec }
        do_ip_allocations('free', machine_def.flatten.map { |m| m.to_spec })
      end

      desc "perform an MCollective ping against these machines"
      sbtask :mping do
        hosts = []
        machine_def.accept do |child_machine_def|
          if child_machine_def.respond_to?(:mgmt_fqdn)
            hosts << child_machine_def.mgmt_fqdn
          end
        end
        found = false
        50.times do
          found = mco_client("rpcutil") do |mco|
            hosts.to_set.subset?(mco.discover.to_set)
          end

          sleep 1
          break if found
        end

        fail("nodes #{hosts.join(" ")} not checked in to mcollective") unless found
        logger.info "all nodes found in mcollective #{hosts.size}"
      end

      namespace :puppet do
        desc "sign outstanding Puppet certificate signing requests for these machines"
        sbtask :sign do
          hosts = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              hosts << child_machine_def.mgmt_fqdn
            end
          end

          include Support::MCollectivePuppet
          ca_sign(hosts) do
            on :success do |vm|
              logger.info "successfully signed cert for #{vm}"
            end
            on :failed do |vm|
              logger.warn "failed to signed cert for #{vm}"
            end
            on :unaccounted do |vm|
              logger.warn "cert not signed for #{vm} (unaccounted for)"
            end
          end
        end

        desc "wait for puppet to complete its run on these machines"
        sbtask :wait do
          hosts = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              hosts << child_machine_def.mgmt_fqdn
            end
          end

          include Support::MCollectivePuppet
          start_time = Time.now
          wait_for_complete(hosts) do
            on :transitioned do |vm, from, to|
              logger.debug "#{vm}: #{from} -> #{to} (#{Time.now})"
            end
            on :passed do |vm|
              logger.info "successful Puppet run for #{vm} (#{Time.now - start_time} sec)"
            end
            on :failed do |vm|
              logger.warn "failed Puppet run for #{vm} (#{Time.now - start_time} sec)"
            end
            on :timed_out do |vm, result|
              logger.warn "Puppet run timed out for for #{vm} (#{result})"
            end
            has :failed do |vms|
              fail("Puppet runs failed for #{vms.join(", ")}")
            end
            has :timed_out do |vms_with_results|
              fail("Puppet runs timed out for #{vms_with_results.map { |vm, result| "#{vm} (#{result})" }.join(", ")}")
            end
          end
        end

        desc "run Puppet on these machines"
        sbtask :run do
          hosts = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              hosts << child_machine_def.mgmt_fqdn
            end
          end

          success = mco_client("puppetd") do |mco|
            engine = PuppetRoll::Engine.new({:concurrency => 5}, [], hosts, PuppetRoll::Client.new(hosts, mco))
            engine.execute()
            pp engine.get_report()
            engine.successful?
          end

          fail("some nodes have failed their puppet runs") unless success
        end

        desc ""
        sbtask :clean do
          hosts = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              hosts << child_machine_def.mgmt_fqdn
            end
          end

          include Support::MCollectivePuppet
          ca_clean(hosts) do
            on :success do |vm|
              logger.info "successfully removed cert for #{vm}"
            end
            on :failed do |vm|
              logger.warn "failed to remove cert for #{vm}"
            end
          end
        end

      end

      desc "clean away all traces of these machines"
      # Note that the ordering here is important - must have killed VMs before
      # removing their puppet cert, otherwise we have a race condition
      task :clean => ['clean_nodes', 'puppet:clean']
      desc "frees up ip and vip allocation of these machines"
      task :free_ip_allocation => ['free_ips', 'free_vips']

      sbtask :clean_nodes do
        computecontroller = Compute::Controller.new
        computecontroller.clean(machine_def.to_specs) do
          on :success do |vm, msg|
            logger.info "cleaned #{vm}"
          end
          on :failure do |vm, msg|
            logger.error "#{vm} failed to clean: #{msg}"
          end
          on :unaccounted do |vm|
            logger.warn "VM was unaccounted for: #{vm}"
          end
        end
      end

      namespace :orc do
        desc "deploys the up2date version of the artifact according to the cmdb using orc"
        sbtask :resolve do

          machine_def.accept do |child_machine_def|
            if child_machine_def.kind_of? Stacks::AppService
              app_service = child_machine_def
              factory = Orc::Factory.new(
                  :application=>app_service.application,
                  :environment=>app_service.environment.name
              )
              factory.cmdb_git.update
              factory.engine.resolve()
            end
          end
        end
      end


      desc "carry out all appropriate tests on these machines"
      sbtask :test do
        machine_def.accept do |child_machine_def|
          specpath = File.dirname(__FILE__) + "/../stacktests/#{child_machine_def.clazz}/*.rb"
          describe "#{child_machine_def.clazz}.#{child_machine_def.name}" do
            Dir[specpath].each do |file|
              require file
              test = File.basename(file, '.rb')
              it_behaves_like test, child_machine_def
            end
          end
        end
        RSpec::Core::Runner.run(['--format', 'CI::Reporter::RSpec'], $stderr, $stdout)
      end
    end
  end
end
