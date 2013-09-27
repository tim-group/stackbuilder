require 'stacks/hosts/namespace'

module Stacks::Hosts::HostPolicies
  def self.ha_group()
    Proc.new do |host, machine|
      if machine.respond_to? :availability_group and machine.availability_group != nil
        member_of_group_exists = false
        host.machines.each do |allocated_machine|
          if allocated_machine.respond_to? :availability_group and machine.availability_group == allocated_machine.availability_group
            member_of_group_exists = true
          end
        end
        !member_of_group_exists
      else
        true
      end
    end
  end

  def self.do_not_overallocated_ram_policy
    Proc.new do |host, machine|
      host_ram = Integer(host.ram)
      if host_ram > 0
        allocated_ram = 0
        host.machines.each do |allocated_machine|
          allocated_ram = allocated_ram + Integer(allocated_machine.ram)
        end
        available_ram = host_ram - allocated_ram
        available_ram >= Integer(machine.ram)
        # override to always return true for now
        true
      else
        true
      end
    end
  end

  def self.do_not_overallocated_disk_policy
    Proc.new do |host, machine|
      true
    end
  end

end
