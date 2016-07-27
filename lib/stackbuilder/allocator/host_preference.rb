require 'stackbuilder/allocator/namespace'

module StackBuilder::Allocator::HostPreference
  # prefer kvm hosts without the "data" partition if the vm doesn't need it
  def self.prefer_no_data
    Proc.new { |host| host.storage["data"].nil? ? -1 : 1 }
  end

  def self.fewest_machines
    Proc.new { |host| host.machines.size }
  end

  def self.alphabetical_fqdn
    Proc.new { |host| host.fqdn }
  end

  def self.most_available_ram
  end

  def self.most_available_disk
  end

  # FIXME: Need to change this in the future
  def self.prefer_not_g9
    Proc.new { |host| host.allocation_tags.include?('Gen9') ? 10 : 0 }
  end
end
