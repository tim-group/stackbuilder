$LOAD_PATH << '/opt/orc/lib/ruby/site_ruby'
$LOAD_PATH << '/usr/local/lib/site_ruby/timgroup'
require 'orc/util/option_parser'
$LOAD_PATH.delete('/usr/local/lib/site_ruby/timgroup')
$LOAD_PATH.delete('/opt/orc/lib/ruby/site_ruby')
require 'rake'
require 'pp'
require 'yaml'
require 'rubygems'
require 'stackbuilder/stacks/environment'
require 'stackbuilder/stacks/inventory'
require 'stackbuilder/support/zamls'
require 'stackbuilder/support/mcollective'
require 'stackbuilder/support/mcollective_puppet'
require 'stackbuilder/support/nagios'
require 'stackbuilder/support/subscription'

require 'set'
require 'rspec'
require 'stackbuilder/compute/controller'
require 'stackbuilder/stacks/factory'
require 'stackbuilder/stacks/core/actions'
require 'thread'

# XXX refactor this somehow, causes warnings in new rubys. hide the warnings for now
# rubocop:disable Style/ClassVars
warn_level = $VERBOSE
$VERBOSE = nil
@@factory = @factory = Stacks::Factory.new
$VERBOSE = warn_level
# rubocop:enable Style/ClassVars

def logger
  warn_level = $VERBOSE
  $VERBOSE = nil
  ret = @@factory.logger
  $VERBOSE = warn_level
  ret
end

include Rake::DSL
include Support::MCollective
extend Stacks::Core::Actions

environment_name = ENV.fetch('env', 'dev')
if (environment = @factory.inventory.find_environment(environment_name)).nil?
  logger.error "environment \"#{environment_name}\" does not exist"
  exit 1
end

RSpec::Core::Runner.disable_autorun!
config = RSpec.configuration
config.color_enabled = true
ENV['CI_REPORTS'] = 'build/spec/reports/'

####
# TODO
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
      block.call
    rescue StandardError => e
      logger.failed(name)
      raise e
    end

    logger.passed(name)
  end
end

@subscription = Subscription.new
@subscription.start(["provision.*", "puppet_status"])

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
      used_percentage = "#{(used.to_f / total.to_f * 100).round}%" rescue 0
      stats["#{storage_type}(GB)".to_sym] = "#{arch}: #{used}/#{total} #{used_percentage}"
      stats
    end
  end

  def order(headers)
    headers.inject([]) do |order, header|
      case header
      when :fqdn                then order[0] = header
      when :vms                 then order[1] = header
      when 'memory(GB)'.to_sym  then order[2] = header
      when 'os(GB)'.to_sym      then order[3] = header
      when 'data(GB)'.to_sym    then order[4] = header
      else order.push(header)
      end
      order
    end.select { |header| !header.nil? }
  end

  @total = Hash.new(0)
  @total_str = lambda { |a, b| sprintf("%d/%d %2.0f%%", a, b, 100.0 * a / b) }
  def kvm_hosts_tabulate_sum_totals(header, value)
    return 0 if value.size == 0

    total_width = 0
    case header.to_s
    when 'vms'
      @total[:vms] += value.to_i
      total_width = @total[:vms].to_s.size
    when 'memory(GB)'
      re = /^(\d+)\/(\d+)/.match(value)
      @total[:mem_used] += re[1].to_i
      @total[:mem_avail] += re[2].to_i
      total_width = @total_str.call(@total[:mem_used], @total[:mem_avail]).to_s.size
    when 'os(GB)'
      re = /^\w+: (\d+)\/(\d+)/.match(value)
      @total[:os_used] += re[1].to_i
      @total[:os_avail] += re[2].to_i
      total_width = @total_str.call(@total[:os_used], @total[:os_avail]).to_s.size
    when 'data(GB)'
      re = /^\w+: (\d+)\/(\d+)/.match(value)
      @total[:data_used] += re[1].to_i
      @total[:data_avail] += re[2].to_i
      total_width = @total_str.call(@total[:data_used], @total[:data_avail]).to_s.size
    end
    total_width + 1
  end

  # XXX output not very pretty, percentages not aligned
  def kvm_hosts_tabulate(data)
    require 'collimator'
    include Collimator
    require 'set'

    all_headers = data.inject(Set.new) { |acc, (_fqdn, header)| acc.merge(header.keys) }

    ordered_headers = order(all_headers)
    header_widths = data.sort.inject({}) do |ordered_header_widths, (_fqdn, data_values)|
      row = ordered_headers.inject([]) do |row_values, header|
        value = data_values[header] || ""

        # determine greatest width
        total_width = kvm_hosts_tabulate_sum_totals(header, value)
        width = value.size > header.to_s.size ? value.size + 1 : header.to_s.size + 1
        width = total_width > width ? total_width : width
        if !ordered_header_widths.key?(header)
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
    total_list = [
      "total",
      "#{@total[:vms]}",
      @total_str.call(@total[:mem_used], @total[:mem_avail]),
      @total_str.call(@total[:os_used], @total[:os_avail])
    ]
    # data(GB) not present in env=dev
    total_list.push(@total_str.call(@total[:data_used], @total[:data_avail])) if @total[:data_avail] > 0
    Table.row(total_list)

    Table.header("KVM host machines audit")
    ordered_headers.each do |header|
      width = header_widths[header] rescue header.to_s.size
      Table.column(header.to_s, :width => width, :padding => 1, :justification => :left)
    end
    Table.tabulate
  end

  def kb_to_gb(value)
    ((value.to_f / (1024 * 1024) * 100).round / 100.0)
  end

  def convert_hash_values_from_kb_to_gb(result_hash)
    gb_hash = result_hash.each.inject({}) do |result, (key, value)|
      if value.is_a?(Hash)
        result[key] = convert_hash_values_from_kb_to_gb(value)
      elsif value.is_a?(String) || value.is_a?(Symbol)
        result[key] = value
      else
        result[key] = kb_to_gb(value).to_f.floor
      end
      result
    end
    gb_hash
  end

  def stats_for(host)
    ram_stats = convert_hash_values_from_kb_to_gb(StackBuilder::Allocator::PolicyHelpers.ram_stats_of(host))
    storage_stats = convert_hash_values_from_kb_to_gb(StackBuilder::Allocator::PolicyHelpers.storage_stats_of(host))
    vm_stats = StackBuilder::Allocator::PolicyHelpers.vm_stats_of(host)
    merge = [storage_stats_to_string(storage_stats), vm_stats, ram_stats_to_string(ram_stats)]
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
    hosts = @factory.host_repository.find_compute_nodes(environment.options[:primary_site])
    kvm_hosts_tabulate(details_for(hosts.hosts))
  end

  desc 'run to_enc on all nodes'
  task :dump_enc do
    environment.environments.sort.each do |envname, env|
      next if envname == 'lon' # XXX 15.07.15 mmazurek/scarytom: special case 'lon' until it's fixed
      env.flatten.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }.each do |stack|
        puts "running to_enc on #{stack.hostname}.#{stack.domain}/#{envname}:"
        puts ZAMLS.to_zamls(stack.to_enc)
      end
    end
  end

  desc 'run to_spec on all nodes'
  task :dump_spec do
    environment.environments.sort.each do |envname, env|
      next if envname == 'lon' # XXX 15.07.15 mmazurek/scarytom: special case 'lon' until it's fixed
      env.flatten.sort { |a, b| a.hostname + a.domain <=> b.hostname + b.domain }.each do |stack|
        puts "running to_spec on #{stack.hostname}.#{stack.domain}/#{envname}:"
        puts ZAMLS.to_zamls(stack.to_spec)
      end
    end
  end

  def get_defined_machines(environment)
    e = []
    environment.environments.each { |_envname, env| e += env.flatten }
    hostnames = e.map(&:hostname)
    machines = e.map(&:to_spec)
    [hostnames, machines]
  end

  def get_allocated_machines(sites)
    hostnames = []
    domains = Hash[]
    storage = Hash[]
    sites.each do |site|
      compute_nodes = @factory.host_repository.find_compute_nodes(site, true).hosts
      hostnames += compute_nodes.map(&:allocated_machines).flatten.map { |vm| vm[:hostname] }
      domains.merge!(compute_nodes.map(&:domains).reduce({}, :merge))
      storage[site] = compute_nodes.map(&:storage) # list of hashes, don't merge in case there are duplicates
    end
    [hostnames, domains, storage]
  end

  def rogue_check_allocation(defined_hostnames, allocated_hostnames)
    # rogue1 = defined_hostnames - allocated_hostnames
    # puts sprintf("defined, but not allocated (%d):", rogue1.size)
    # rogue1.each { |node| puts "  #{node}" }

    rogue2 = allocated_hostnames - defined_hostnames
    puts sprintf("allocated, but not defined (%d):", rogue2.size)
    rogue2.each { |node| puts "  #{node}" }
  end

  # rubocop:disable Style/Next
  def rogue_check_resources(defined_machines, allocated_domains)
    puts "checking vm properties..."
    allocated_domains.each do |afqdn, adata|
      dhost = defined_machines.detect { |dh| sprintf("%s.%s", dh[:hostname], dh[:domain]) == afqdn }
      next if dhost.nil?

      if dhost[:vcpus].to_i != adata[:vcpus]
        if dhost[:vcpus].to_i != 0
          puts sprintf("  %s.%s: defined cpus: %d; reality: %d", dhost[:hostname], dhost[:domain],
                       dhost[:vcpus], adata[:vcpus])
          # else
          # XXX how to figure out the default value?
        end
      end

      if dhost[:ram].to_i != adata[:memory]
        if dhost[:ram].to_i != 0
          puts sprintf("  %s.%s: defined memory: %d; reality: %d", dhost[:hostname], dhost[:domain],
                       dhost[:ram], adata[:memory])
          # else
          # XXX how to figure out the default value?
        end
      end
    end
  end

  # XXX incomplete, too many special cases. return to this once everything is migrated to NNI
  def rogue_check_missing_storage(defined_machines, allocated_storage, _allocated_hostnames)
    puts "checking missing or misallocated storage..."
    defined_machines.each do |dhost|
      dhost[:storage].each do |mount_point, p|
        if allocated_storage[dhost[:fabric]].nil?
          puts "  fabric \"#{dhost[:fabric]}\" has no storage allocated at all"
          next
        end

        astorage = []
        allocation_name = dhost[:hostname] + mount_point.to_s.gsub('/', '_').gsub(/_$/, '')
        allocated_storage[dhost[:fabric]].each do |as|
          if as[p[:type]].nil?
            puts "  #{dhost[:hostname]}: no storage type \"#{p[:type]}\" on fabric \"#{dhost[:fabric]}\" allocated"
            next
          end
          a = as[p[:type]][:existing_storage][allocation_name.to_sym]
          astorage << a if !a.nil?
        end

        if astorage.size != 1
          puts "  #{dhost[:hostname]}: storage \"#{allocation_name}\" found on #{astorage.size} compute nodes"
          next
        end

        astorage_size = astorage[0]
        psize = p[:size].to_i * 1024 * 1024
        if astorage_size.to_i == psize
          puts "  #{dhost[:hostname]}: size for storage \"#{allocation_name}\" is \"#{astorage_size}\", expected " \
            "\"#{psize * 1024 / 1000}\" -- was this vm created manually?"
          next
        end

        psize = p[:size].to_i * 1024 * 1024 * 1024 / 1000
        if astorage_size.to_i != psize
          puts "  #{dhost[:hostname]}: size mismatch for storage \"#{allocation_name}\", is \"#{astorage_size}\", " \
            "should be \"#{psize}\""
          next
        end
      end
    end
  end
  # rubocop:enable Style/Next

  desc 'find inconsistency between stackbuilder-config and reality'
  task :find_rogue do
    defined_hostnames, _defined_machines = get_defined_machines(environment)
    allocated_hostnames, _allocated_domains, _allocated_storage = get_allocated_machines(%w(oy pg st ci))

    rogue_check_allocation(defined_hostnames, allocated_hostnames)
    # rogue_check_resources(defined_machines, allocated_domains)
    # rogue_check_missing_storage(defined_machines, allocated_storage, allocated_hostnames)
  end

  require 'set'
  machine_names = Set.new
  environment.accept do |machine_def|
    if machine_def.respond_to?(:mgmt_fqdn)
      rake_task_name = machine_def.mgmt_fqdn.to_sym
    else
      rake_task_name = machine_def.name.to_sym
    end

    namespace rake_task_name do
      RSpec::Core::Runner.disable_autorun!
      if machine_names.include?(rake_task_name)
        fail "Duplicate machine name detected: #{machine_def.name} in #{machine_def.environment.name}. " \
          "Look for a stack that has the same name as the server being created.\neg.\n" \
          " stack '#{machine_def.name}' do\n  app '#{machine_def.name}'"
      end
      machine_names << "#{machine_def.environment.name}:#{machine_def.name}"

      desc "outputs the specs for these machines, in the format to feed to the provisioning tools"
      task :to_specs do
        puts ZAMLS.to_zamls(machine_def.to_specs)
      end

      desc "outputs the specs for these machines, in the format to feed to the provisioning tools"
      task :to_vip_spec do
        puts ZAMLS.to_zamls(machine_def.to_vip_spec(:primary_site))
      end

      if machine_def.respond_to? :to_enc
        desc "External Node Classifiers; fed to puppet"
        task :to_enc do
          puts ZAMLS.to_zamls(machine_def.to_enc)
        end
      end

      # make orc resolve available on stacks (containers) that have app servers, and individual app servers
      namespace :orc do
        if machine_def.is_a? Stacks::Services::AppServer
          desc "orc resolve #{machine_def.virtual_service.application}"
          sbtask :resolve do
            factory = Orc::Factory.new(
              :application => machine_def.virtual_service.application,
              :environment => machine_def.environment.name
            )
            factory.cmdb_git.update
            factory.engine.resolve
          end
        else
          applications = Set.new
          machine_def.accept do |child_machine_def|
            next unless child_machine_def.is_a? Stacks::Services::AppServer
            applications << child_machine_def.virtual_service.application
          end
          if applications.to_a.size > 0
            desc "orc resolve #{applications.to_a.join(', ')}"
            sbtask :resolve do
              applications.to_a.each do |application|
                factory = Orc::Factory.new(
                  :application => application,
                  :environment => machine_def.environment.name
                )
                factory.cmdb_git.update
                factory.engine.resolve
              end
            end
          end
        end
      end

      desc "perform all steps required to create and configure the machine(s)"
      task :provision => ['allocate_vips', 'launch', 'puppet:sign', 'puppet:poll_sign', 'puppet:wait'] do |t|
        namespace = t.name.sub(/:provision$/, '')
        Rake::Task[namespace + ':orc:resolve'].invoke if Rake::Task.task_defined?(namespace + ':orc:resolve')
        Rake::Task[namespace + ':cancel_downtime'].invoke
      end

      desc "perform a clean followed by a provision"
      task :reprovision => %w(clean provision)

      desc "allocate these machines to hosts (but don't actually launch them - this is a dry run)"
      sbtask :allocate do
        get_action("allocate").call(@factory.services, machine_def)
      end

      desc "launch these machines"
      sbtask :launch do
        get_action("launch").call(@factory.services, machine_def)
      end

      desc "new hosts model auditing"
      sbtask :audit_hosts do
        hosts = @factory.host_repository.find_compute_nodes("st")
        hosts.allocate(machine_def.flatten)
        hosts.hosts.each do |host|
          pp host.fqdn
          host.allocated_machines.each do |machine|
            puts "\t #{machine.mgmt_fqdn}" unless machine.nil?
          end
        end
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
          vips << child_machine_def.to_vip_spec(:primary_site) if child_machine_def.respond_to?(:to_vip_spec)
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
          vips << child_machine_def.to_vip_spec(:primary_site) if child_machine_def.respond_to?(:to_vip_spec)
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
          result = @subscription.wait_for_hosts("provision.*", puppet_certs_to_sign, 600)
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
            on :already_signed do |machine|
              logger.warn "cert for #{machine} already signed, skipping"
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

          run_result = @subscription.wait_for_hosts("puppet_status", hosts, 5400)

          run_result.all.each do |vm, status|
            logger.info "puppet run: #{status} for #{vm} - (#{Time.now - start_time} sec)"
          end

          unless run_result.all_passed?
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
            engine.execute
            pp engine.get_report
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
      task :free_ip_allocation => %w(free_ips free_vips)

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
            logger.info "successfully scheduled #{downtime_secs} seconds downtime for #{response_hash[:machine]} " \
              "result: #{response_hash[:result]}"
          end
          on :failed do |response_hash|
            logger.info "failed to schedule #{downtime_secs} seconds downtime for #{response_hash[:machine]} " \
              "result: #{response_hash[:result]}"
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
            logger.info "successfully cancelled downtime for #{response_hash[:machine]} " \
              "result: #{response_hash[:result]}"
          end
          on :failed do |response_hash|
            logger.info "failed to cancel downtime for #{response_hash[:machine]} result: #{response_hash[:result]}"
          end
        end
      end

      sbtask :showvnc do
        hosts = []
        machine_def.accept do |child|
          hosts << child.name if child.is_a? Stacks::MachineDef
        end
        mco_client("libvirt") do |mco|
          mco.fact_filter "domain=/(st|ci)/"
          results = {}
          hosts.each do |host|
            mco.domainxml(:domain => host) do |result|
              xml = result[:body][:data][:xml]
              sender = result[:senderid]
              unless xml.nil?
                matches = /type='vnc' port='(\-?\d+)'/.match(xml)
                fail "Pattern match for vnc port was nil for #{host}\n XML output:\n#{xml}" if matches.nil?
                fail "Pattern match for vnc port contains no captures for #{host}\n XML output:\n#{xml}" \
                  if matches.captures.empty?
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
