require 'stacks/hosts/namespace'

module StackBuilder::Allocator::HostPolicies
  def self.ha_group()
    Proc.new do |host, machine|
      result = { :passed => true }
      if machine.respond_to? :availability_group and machine.availability_group != nil
        host.machines.each do |allocated_machine|
          if allocated_machine.respond_to? :availability_group and machine.availability_group == allocated_machine.availability_group
            result = { :passed => false, :reason => "already running  #{allocated_machine.name}, which is in same availability group" }
          end
        end
      end
      result
    end
  end

  def self.do_not_overallocated_ram_policy
    Proc.new do |host, machine|
      result = { :passed => true }
      host_ram = Integer(host.ram)
      host_reserve_ram = 2097152 #2 GB
      if host_ram > 0
        allocated_ram = 0
        host.machines.each do |allocated_machine|
          allocated_ram = allocated_ram + Integer(allocated_machine.ram)
        end
        available_ram = (host_ram - allocated_ram) - host_reserve_ram
        if available_ram < Integer(machine.ram)
          result = { :passed => false, :reason => "unable to fulfil ram requirement of #{machine.ram} because only #{available_ram} is available. Memory stats: #{allocated_ram+host_reserve_ram}/#{host_ram}" }
        end
      end
      result
    end
  end

  def self.do_not_overallocated_disk_policy
    Proc.new do |host, machine|
      { :passed => true }
    end
  end

end
