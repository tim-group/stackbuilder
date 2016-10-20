require 'stackbuilder/allocator/namespace'

module StackBuilder::Allocator::HostPreference
  # prefer kvm hosts without the "data" partition if the vm doesn't need it
  def self.prefer_no_data
    Proc.new { |host, _machine_spec| host.storage["data"].nil? ? -10 : 10 }
  end

  def self.fewest_machines
    Proc.new { |host, _machine_spec| host.machines.size }
  end

  def self.alphabetical_fqdn
    Proc.new { |host, _machine_spec| host.fqdn }
  end

  def self.most_available_ram
  end

  def self.most_available_disk
  end

  # FIXME: Need to change this in the future
  def self.prefer_not_g9
    Proc.new { |host, _machine_spec| host.facts['allocation_tags'].include?('Gen9') ? 50 : 0 }
  end

  def self.prefer_diverse_vm_rack_distribution
    Proc.new do |host, machine_spec|
      if host.availability_groups_in_rack.key?(machine_spec[:availability_group])
        host.availability_groups_in_rack[machine_spec[:availability_group]] * 20
      else
        0
      end
    end
  end
end
