require 'stacks/hosts/namespace'
require 'stacks/hosts/hosts'

class Stacks::Hosts::HostRepository
  attr_accessor :machine_repo
  attr_reader :preference_functions

  def initialize(args)
    @machine_repo = args[:machine_repo]
    @preference_functions = args[:preference_functions]
    @compute_node_client = args[:compute_node_client]
  end

  def find_current(fabric)
    result = @compute_node_client.audit_hosts(fabric)
    hosts = []
    result.each do |fqdn, attr|
      vms = []
      attr[:active_domains].each do |vm_hostname|
        vms << machine_repo.find_by_hostname(vm_hostname)
      end
      host = Stacks::Hosts::Host.new(fqdn, :preference_functions => preference_functions)
      host.allocated_machines = vms
      hosts << host
    end

    Stacks::Hosts::Hosts.new(:hosts => hosts, :preference_functions => preference_functions)
  end
end

