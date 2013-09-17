require 'stacks/hosts/namespace'

module Stacks::Hosts::HostPreference
  def self.fewest_machines()
    Proc.new do |host|
      host.machines.size
    end
  end

  def self.alphabetical_fqdn()
    Proc.new do |host|
      host.fqdn
    end
  end

  def self.most_available_ram()
  end

  def self.most_available_disk()
  end
end
