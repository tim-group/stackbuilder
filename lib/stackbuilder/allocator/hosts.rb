require 'stackbuilder/allocator/namespace'
require 'stackbuilder/allocator/host'

class StackBuilder::Allocator::Hosts
  attr_reader :hosts

  def initialize(args)
    @hosts = args[:hosts]
    @logger = args[:logger] # XXX needing to use "unless @logger.nil?" is not good

    fail 'Cannot initialise Host Allocator with no hosts to allocate!' if hosts.empty?
    hosts.each do |host|
      host.preference_functions = args[:preference_functions]
    end
  end

  public

  def do_allocation(specs)
    allocated_machines = Hash[hosts.map do |host|
      host.allocated_machines.map do |machine|
        [machine, host.fqdn]
      end
    end.flatten(1)]

    already_allocated = allocated_machines.reject do |machine, _host|
      !specs.include?(machine)
    end

    {
      :already_allocated => already_allocated,
      :newly_allocated => allocate(specs)
    }
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
        unless @logger.nil?
          @logger.debug("Allocating #{machine[:hostname]} -- skipping #{host.fqdn} - #{reasons.size} " \
                        "reasons:\n          * #{reason_message}")
        end
        allocation_denials << "unable to allocate to #{host.fqdn} because it is [#{reason_message}]"
      end
      !allocation_check_result[:allocatable]
    end

    if candidate_hosts.empty?
      fail "Unable to allocate #{machine[:hostname]} due to policy violation:\n  #{allocation_denials.join("\n  ")}"
    end

    candidate_hosts = candidate_hosts.sort_by(&:preference)

    unless @logger.nil?
      @logger.debug("kvm host preference list:")
      candidate_hosts.each { |p| @logger.debug("  #{p.preference}") }
    end

    candidate_hosts[0]
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

    allocated_machines = Hash[unallocated_machines.map do |machine|
      host = find_suitable_host_for(machine)
      host.provisionally_allocate(machine)
      [machine, host.fqdn]
    end]

    return_map = {}
    allocated_machines.each do |machine, host|
      return_map[host] = [] unless return_map[host]
      return_map[host] << machine
    end

    return_map
  end
end
