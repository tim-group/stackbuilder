require 'stacks/hosts/namespace'
require 'stacks/hosts/host'

class Stacks::Hosts::Hosts
  attr_accessor :hosts
  def initialize(args)
    @hosts = args[:hosts]
    hosts.each do |host|
      host.set_preference_functions(args[:preference_functions])
    end
  end

  private
  def find_suitable_host_for(machine)
    candidate_hosts = hosts.reject do |host|
      !host.can_allocate(machine)
    end.sort_by do |host|
      host.preference(machine)
    end

    raise "unable to allocate #{machine.name} due to policy violation" if candidate_hosts.size==0
    candidate_hosts[0]
  end

  def unallocated_machines(machines)
    allocated_machines = []
    hosts.each do |host|
      host.allocated_machines.each do |machine|
        allocated_machines << machine
      end
    end

    return machines - allocated_machines
  end

  public

  def new_machine_allocation()
    hash = []
    hosts.map do |host|
      host.provisionally_allocated_machines.each do |machine|
        hash << [machine, host]
      end
    end

    Hash[hash]
  end

  def allocated_machines(machines)
    hash = []
    hosts.map do |host|
      intersection =  host.allocated_machines.to_set & machines.to_set
      intersection.map do |machine|
        hash << [machine, host]
      end
    end

    Hash[hash]
  end

  def allocate(machines)
    unallocated_machines = unallocated_machines(machines)
    unallocated_machines.each do |machine|
      host = find_suitable_host_for(machine)
      host.provisionally_allocate(machine)
    end
  end

  def to_unlaunched_specs
    Hash[@hosts.map do |host|
      specs = host.provisionally_allocated_machines.map do |machine|
        machine.to_spec
      end
      [host.fqdn, specs]
    end].reject {|host, specs| specs.size==0}
  end
end
