require 'stacks/hosts/namespace'

module Stacks::Hosts::HostPreference
  def self.least_machines()
    Proc.new do |host|
      host.machines.size
    end
  end

  def self.alphabetical_fqdn()
    Proc.new do |host|
      host.fqdn
    end
  end


  #  enough_ram_policy = Proc.new do |host, machine|
  #    host.ram - machine.ram >0
  #  end
end