require 'stackbuilder/allocator/namespace'
require 'stackbuilder/allocator/host'
require 'stackbuilder/support/logger'

class StackBuilder::Allocator::Hosts
  attr_reader :hosts
  attr_reader :availability_group_rack_distribution

  def initialize(args)
    @hosts = args[:hosts]
    fail 'Cannot initialise Host Allocator with no hosts to allocate!' if hosts.empty?

    hosts.each do |host|
      host.preference_functions = args[:preference_functions]
      host.hosts = self
    end
  end

  def without(hosts)
    return self if hosts.empty?

    excluded_host_fqdns = hosts.map(&:fqdn)
    reduced_hosts = @hosts.reject { |h| excluded_host_fqdns.include?(h.fqdn) }
    StackBuilder::Allocator::Hosts.new(:hosts => reduced_hosts, :preference_functions => @hosts.first.preference_functions)
  end

  public

  def do_allocation(specs, best_effort = false)
    allocated_machines = Hash[hosts.map do |host|
      host.allocated_machines.map do |machine|
        [machine, host.fqdn]
      end
    end.flatten(1)]

    already_allocated = allocated_machines.reject do |machine, _host|
      !specs.include?(machine)
    end

    result_map = allocate(specs)
    result_map[:already_allocated] = already_allocated

    return result_map if best_effort || result_map[:failed_to_allocate].empty?

    result_map[:failed_to_allocate].each do |machine, reason|
      fail "Unable to allocate #{machine[:hostname]} due to policy violation:\n  #{reason}"
    end
  end

  def availability_group_rack_distribution
    rack_availability_groups = {}
    hosts.each do |host|
      rack = host.facts['rack']
      rack_availability_groups[rack] = {} unless rack_availability_groups.key? rack

      host.machines.each do |machine|
        next if !machine[:availability_group]
        if rack_availability_groups[rack].key?(machine[:availability_group])
          rack_availability_groups[rack][machine[:availability_group]] += 1
        else
          rack_availability_groups[rack][machine[:availability_group]] = 1
        end
      end
    end
    rack_availability_groups
  end

  private

  def find_suitable_host_for(machine)
    allocation_denials = []

    fail "Unable to allocate #{machine[:hostname]} as there are no hosts available" if hosts.empty?

    candidate_hosts = hosts.reject do |host|
      allocation_check_result = host.can_allocate(machine)
      unless allocation_check_result[:allocatable]
        reasons = allocation_check_result[:reasons]
        reason_message = if reasons.empty?
                           'unsuitable for an unknown reason'
                         else
                           allocation_check_result[:reasons].join("; ")
                         end
        logger(Logger::DEBUG) { "cannot allocate #{machine[:hostname]} on #{host.fqdn} - #{reasons.size} reason(s):" }
        logger(Logger::DEBUG) { "  #{reason_message}" }
        allocation_denials << "unable to allocate to #{host.fqdn} because it is [#{reason_message}]"
      end
      !allocation_check_result[:allocatable]
    end

    return ['failure', allocation_denials] if candidate_hosts.empty?

    candidate_hosts = candidate_hosts.sort_by { |host| host.preference(machine) }
    logger(Logger::DEBUG) { "KVM preference list:" }
    logger(Logger::DEBUG) { "[prefer_not_g9, prefer_no_data, fewest_machines, diverse_vm_rack_distribution, fqdn]" }
    candidate_hosts.each { |p| logger(Logger::DEBUG) { "  #{p.preference(machine)}" } }
    ['success', candidate_hosts[0]]
  end

  private

  def unallocated_machines(machines)
    allocated_machines = []
    hosts.each do |host|
      host.allocated_machines.each do |machine|
        allocated_machines << machine
      end
    end

    machines - allocated_machines
  end

  public

  def allocate(machines)
    unallocated_machines = unallocated_machines(machines)

    successful_allocations = {}
    failed_allocations = {}

    unallocated_machines.each do |machine|
      result = find_suitable_host_for(machine)

      if result[0] == 'failure'
        failed_allocations[machine] = result[1].join("\n  ")
      else
        host = result[1]
        host.provisionally_allocate(machine)
        successful_allocations[host.fqdn] = [] unless successful_allocations[host.fqdn]
        successful_allocations[host.fqdn] << machine
      end
    end

    {
      :newly_allocated => successful_allocations,
      :failed_to_allocate => failed_allocations
    }
  end
end
