require 'stacks/hosts/namespace'

module Stacks::Hosts::HostPolicies
  def self.ha_group()
    Proc.new do |host, machine|
      if machine.availability_group != nil
        member_of_group_exists = false
        host.machines.each do |allocated_machine|
          if machine.responds_to?:availability_group && machine.availability_group == allocated_machine.availability_group
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
  end

  def self.do_not_overallocated_disk_policy
  end

end
