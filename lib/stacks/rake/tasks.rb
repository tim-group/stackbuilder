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
require 'support/nagios'
require 'set' # ci/reporter/rspec should require this but doesn't

require 'ci/reporter/rspec'
require 'set'
require 'rspec'
require 'compute/controller'
require 'stacks/factory'
require 'stacks/core/actions'
require 'thread'
require 'stacks/subscription'
@@factory = @factory = Stacks::Factory.new

include Rake::DSL
include Support::MCollective
extend Stacks::Core::Actions

environment_name = ENV.fetch('env', 'dev')
environment = @factory.inventory.find_environment(environment_name)

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

def logger
  @@factory.logger
end

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

@@subscription = Subscription.new()
@@subscription.start(["provision.*", "puppet_status"])

namespace :sbx do
  def ram_stats_to_string(ram_stats)
    used = ram_stats[:allocated_ram]
    total = ram_stats[:host_ram]
    used_percentage = "#{(used.to_f / total.to_f * 100).round.to_s.rjust(3)}%" rescue 0
    { 'memory(GB)'.to_sym => "#{used}/#{total} #{used_percentage}" }
  end

  def storage_stats_to_string(storage_stats)
    storage_stats.inject({}) do |stats, (storage_type, value_hash)|
      arch = value_hash[:arch]
      used = value_hash[:used]
      total = value_hash[:total]
      used_percentage = "#{(used.to_f / total.to_f * 100).round.to_s}%" rescue 0
      stats["#{storage_type}(GB)".to_sym] = "#{arch.to_s}: #{used.to_s}/#{total.to_s} #{used_percentage.to_s}"
      stats
    end
  end

  def order(headers)
    order = headers.inject([]) do |order, header|
      case header
       when :fqdn
         order.insert(0, header)
       when :vms
         order.insert(1, header)
        when 'memory(GB)'.to_sym
          order.insert(2, header)
        when 'os(GB)'.to_sym
          order.insert(3, header)
        else
          order.push(header)
      end
      order
    end
    order.select { |header| !header.nil? }
  end

  def tabulate(data)
    require 'collimator'
    include Collimator
    require 'set'
    all_headers = data.inject(Set.new) do |all_headers, (fqdn, header)|
      all_headers.merge(header.keys)
      all_headers
    end
    ordered_headers = order(all_headers)
    ordered_header_widths = data.inject({}) do |ordered_header_widths, (fqdn, data_values)|
      row = ordered_headers.inject([]) do |row_values, header|
        value = data_values[header] || ""
        width = value.size > header.to_s.size ? value.size : header.to_s.size
        if !ordered_header_widths.has_key?(header)
          ordered_header_widths[header] = width
        else
          ordered_header_widths[header] = width if ordered_header_widths[header] < width
        end
        row_values << value
        row_values
      end
      Table.row(row)
      ordered_header_widths
    end

    Table.header("")
    ordered_headers.each do |header|
      width = ordered_header_widths[header] rescue header.to_s.size
      Table.column(header.to_s, :width => width, :padding => 1, :justification => :left)
    end
    Table.tabulate
 end

  def KB_to_GB(value)
    ((value.to_f / (1024 * 1024) * 100).round / 100.0)
  end

  def convert_hash_values_from_KB_to_GB(result_hash)
    gb_hash = result_hash.each.inject({}) do |result, (key, value)|
      if value.is_a?(Hash)
        result[key] = convert_hash_values_from_KB_to_GB(value)
      elsif value.is_a?(String) || value.is_a?(Symbol)
        result[key] = value
      else
        result[key] = KB_to_GB(value).to_f.floor
      end
      result
    end
    gb_hash
  end

  def stats_for(host)
    ram_stats = convert_hash_values_from_KB_to_GB(StackBuilder::Allocator::PolicyHelpers.ram_stats_of(host))
    storage_stats = convert_hash_values_from_KB_to_GB(StackBuilder::Allocator::PolicyHelpers.storage_stats_of(host))
    vm_stats = StackBuilder::Allocator::PolicyHelpers.vm_stats_of(host)
    merge  = [storage_stats_to_string(storage_stats), vm_stats, ram_stats_to_string(ram_stats)]
    merged_stats = Hash[*merge.map(&:to_a).flatten]

    merged_stats[:fqdn] = host.fqdn
    merged_stats
  end

  def details_for(hosts)
    hosts.inject({}) do |data, host|
      stats = stats_for(host)
      data[host.fqdn] = stats
      data
    end
  end

  desc 'Print a report of KVM host CPU/Storage/Memory allocation'
  task :audit_host_machines do
    hosts = @factory.host_repository.find_current(environment.options[:primary_site])
    tabulate(details_for(hosts.hosts))
  end

  task :find_rogue do
    hosts = @factory.host_repository.find_current("local")

    rogue_machines = hosts.hosts.map(&:allocated_machines).flatten().reject { |vm| vm[:in_model] }

    pp rogue_machines
  end

  require 'set'
  machine_names = Set.new
  environment.accept do |machine_def|
    namespace machine_def.name.to_sym do
      RSpec::Core::Runner.disable_autorun!
      raise "Duplicate machine name detected: #{machine_def.name} in #{machine_def.environment.name}. Look for a stack that has the same name as the server being created.\neg.\n stack '#{machine_def.name}' do\n  app '#{machine_def.name}" if machine_names.include?("#{machine_def.environment.name}:#{machine_def.name}")
      machine_names << "#{machine_def.environment.name}:#{machine_def.name}"

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

      desc "perform all steps required to create and configure the machine(s)"
      task :provision => ['allocate_vips', 'launch', 'puppet:sign', 'puppet:poll_sign', 'puppet:wait', 'orc:resolve', 'cancel_downtime']

      desc "perform a clean followed by a provision"
      task :reprovision => ['clean', 'provision']

      desc "allocate these machines to hosts (but don't actually launch them - this is a dry run)"
      sbtask :allocate do
        get_action("allocate").call(@factory.services, machine_def)
      end

      desc "launch these machines"
      sbtask :launch do
        get_action("launch").call(@factory.services, machine_def)
      end

      sbtask :blah do
        hosts = @factory.host_repository.find_current("st")
        hosts.allocated_machines(machine_def.flatten).map do |machine, host|
          logger.info("#{machine.mgmt_fqdn} already allocated to #{host.fqdn}")
        end
      end

      desc "new hosts model auditing"
      sbtask :audit_hosts do
        hosts = @factory.host_repository.find_current("st")
        hosts.allocate(machine_def.flatten)
        hosts.hosts.each do |host|
          pp host.fqdn
          host.allocated_machines.each do |machine|
            unless machine.nil?
              puts "\t #{machine.mgmt_fqdn}"
            end
          end
        end
      end

      sbtask :audit do
        computecontroller = Compute::Controller.new
        pp computecontroller.audit(machine_def.to_specs)
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

      desc "allocate IPs for these virtual services"
      sbtask :allocate_vips do
        vips = []
        machine_def.accept do |child_machine_def|
          vips << child_machine_def.to_vip_spec if child_machine_def.respond_to?(:to_vip_spec)
        end
        if vips.empty?
          logger.info 'no vips to allocate'
        else
          @factory.services.dns.allocate(vips)
        end
      end

      desc "free IPs for these virtual services"
      sbtask :free_vips do
        vips = []
        machine_def.accept do |child_machine_def|
          vips << child_machine_def.to_vip_spec if child_machine_def.respond_to?(:to_vip_spec)
        end
        @factory.services.dns.free(vips)
      end

      desc "free IPs"
      sbtask :free_ips do
        all_specs = machine_def.flatten.map(&:to_spec)
        @factory.services.dns.free(all_specs)
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

        fail("nodes #{hosts.join(' ')} not checked in to mcollective") unless found
        logger.info "all nodes found in mcollective #{hosts.size}"
      end

      def timed_out(start_time, timeout)
        (now - start_time) > timeout
      end

      def now
        Time.now
      end

      namespace :puppet do
        desc "sign outstanding Puppet certificate signing requests for these machines"
        sbtask :sign do
          puppet_certs_to_sign = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              if child_machine_def.needs_signing?
                puppet_certs_to_sign << child_machine_def.mgmt_fqdn
              else
                logger.info "signing not needed for #{child_machine_def.mgmt_fqdn}"
              end
            end
          end
          start_time = Time.now
          result = @@subscription.wait_for_hosts("provision.*", puppet_certs_to_sign, 600)
          result.all.each do |vm, status|
            logger.info "puppet cert signing: #{status} for #{vm} - (#{Time.now - start_time} sec)"
          end
        end

        desc "sign outstanding Puppet certificate signing requests for these machines"
        sbtask :poll_sign do
          puppet_certs_to_sign = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              if child_machine_def.needs_poll_signing?
                puppet_certs_to_sign << child_machine_def.mgmt_fqdn
              else
                logger.info "poll signing not needed for #{child_machine_def.mgmt_fqdn}"
              end
            end
          end

          include Support::MCollectivePuppet
          ca_sign(puppet_certs_to_sign) do
            on :success do |machine|
              logger.info "successfully signed cert for #{machine}"
            end
            on :failed do |machine|
              logger.warn "failed to signed cert for #{machine}"
            end
            on :unaccounted do |machine|
              logger.warn "cert not signed for #{machine} (unaccounted for)"
            end
          end
        end

        desc "wait for puppet to complete its run on these machines"
        sbtask :wait do
          start_time = Time.now
          hosts = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              hosts << child_machine_def.mgmt_fqdn
            end
          end

          run_result = @@subscription.wait_for_hosts("puppet_status", hosts, 5400)

          run_result.all.each do |vm, status|
            logger.info "puppet run: #{status} for #{vm} - (#{Time.now - start_time} sec)"
          end

          if !run_result.all_passed?
            fail("Puppet runs have timed out or failed, see above for details")
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
            engine = PuppetRoll::Engine.new({ :concurrency => 5 }, [], hosts, PuppetRoll::Client.new(hosts, mco))
            engine.execute()
            pp engine.get_report()
            engine.successful?
          end

          fail("some nodes have failed their puppet runs") unless success
        end

        desc "Remove signed certs from puppetmaster"
        sbtask :clean do
          puppet_certs_to_clean = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              if child_machine_def.needs_signing?
                puppet_certs_to_clean << child_machine_def.mgmt_fqdn
              else
                logger.info "removal of cert not needed for #{child_machine_def.mgmt_fqdn}"
              end
            end
          end

          include Support::MCollectivePuppet
          ca_clean(puppet_certs_to_clean) do
            on :success do |machine|
              logger.info "successfully removed cert for #{machine}"
            end
            on :failed do |machine|
              logger.warn "failed to remove cert for #{machine}"
            end
          end
        end
      end

      desc "clean away all traces of these machines"
      # Note that the ordering here is important - must have killed VMs before
      # removing their puppet cert, otherwise we have a race condition
      task :clean => ['schedule_downtime', 'clean_nodes', 'puppet:clean']
      desc "frees up ip and vip allocation of these machines"
      task :free_ip_allocation => ['free_ips', 'free_vips']

      sbtask :clean_nodes do
        computecontroller = Compute::Controller.new
        computecontroller.clean(machine_def.to_specs) do
          on :success do |vm, msg|
            logger.info "successfully cleaned #{vm}: #{msg}"
          end
          on :failure do |vm, msg|
            logger.error "failed to clean #{vm}: #{msg}"
          end
          on :unaccounted do |vm|
            logger.warn "VM was unaccounted for: #{vm}"
          end
        end
      end

      sbtask :schedule_downtime do
        hosts = []
        machine_def.accept do |child_machine_def|
          if child_machine_def.respond_to?(:mgmt_fqdn)
            hosts << child_machine_def
          end
        end

        nagios_helper = Support::Nagios::Service.new
        downtime_secs = 1800 # 1800 = 30 mins
        nagios_helper.schedule_downtime(hosts, downtime_secs) do
          on :success do |response_hash|
            logger.info "successfully scheduled #{downtime_secs} seconds downtime for #{response_hash[:machine]} result: #{response_hash[:result]}"
          end
          on :failed do |response|
            logger.info "failed to schedule #{downtime_secs} seconds downtime for #{response_hash[:machine]} result: #{response_hash[:result]}"
          end
        end
      end

      sbtask :cancel_downtime do
        hosts = []
        machine_def.accept do |child_machine_def|
          if child_machine_def.respond_to?(:mgmt_fqdn)
            hosts << child_machine_def
          end
        end

        nagios_helper = Support::Nagios::Service.new
        nagios_helper.cancel_downtime(hosts) do
          on :success do |response_hash|
            logger.info "successfully cancelled downtime for #{response_hash[:machine]} result: #{response_hash[:result]}"
          end
          on :failed do |response_hash|
            logger.info "failed to cancel downtime for #{response_hash[:machine]} result: #{response_hash[:result]}"
          end
        end
      end

      sbtask :showvnc do
        hosts = []
        machine_def.accept do |child|
          if child.kind_of? Stacks::MachineDef
            hosts << child.name
          end
        end
        mco_client("libvirt") do |mco|
          mco.fact_filter "domain=/(st|ci)/"
          results = {}
          hosts.each do |host|
            mco.domainxml(:domain => host) do |result|
              xml = result[:body][:data][:xml]
              sender = result[:senderid]
              if !xml.nil?
                matches = /type='vnc' port='(\-?\d+)'/.match(xml)
                raise "Pattern match for vnc port was nil for #{host}\n XML output:\n#{xml}" if matches.nil?
                raise "Pattern match for vnc port contains no captures for #{host}\n XML output:\n#{xml}" if matches.captures.empty?
                results[host] = {
                  :host => sender,
                  :port => matches.captures.first
                }
              end
            end
          end
          results.each do |vm, location|
            puts "#{vm}  -> #{location[:host]}:#{location[:port]}"
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
                :application => app_service.application,
                :environment => app_service.environment.name
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
