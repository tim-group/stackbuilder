require 'stacks/hosts/namespace'

module HostPreference
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
end