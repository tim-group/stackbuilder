require 'stackbuilder/allocator/namespace'

module StackBuilder::Allocator::HostPreference
  def self.fewest_machines
    proc do |host|
      host.machines.size
    end
  end

  def self.alphabetical_fqdn
    proc do |host|
      host.fqdn
    end
  end

  def self.most_available_ram
  end

  def self.most_available_disk
  end
end
