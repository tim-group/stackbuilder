require 'stackbuilder/allocator/namespace'
require 'stackbuilder/allocator/hosts'

class StackBuilder::Allocator::HostRepository
  attr_accessor :machine_repo
  attr_reader :preference_functions
  attr_reader :policies

  def initialize(args)
    @machine_repo = args[:machine_repo]
    @preference_functions = args[:preference_functions]
    @compute_node_client = args[:compute_node_client]
    @policies = args[:policies]
  end

  def find_compute_nodes(fabric, audit_domains = false)
    result = @compute_node_client.audit_hosts(fabric, audit_domains)
    hosts = []
    result.each do |fqdn, attr|
      vms = []
      all_domains = attr[:active_domains].concat(attr[:inactive_domains])
      all_domains.each do |vm_hostname|
        vm_object = machine_repo.find_by_hostname(vm_hostname)
        if vm_object.nil?
          vms << { :hostname => vm_hostname, :in_model => false }
        else
          vms << vm_object.to_spec
        end
      end

      host = StackBuilder::Allocator::Host.new(fqdn,
                                               :preference_functions => preference_functions,
                                               :policies => policies,
                                               :ram => attr[:memory],
                                               :storage => attr[:storage],
                                               :allocation_disabled => attr[:allocation_disabled],
                                               :allocation_tag => attr[:allocation_tag])

      host.allocated_machines = vms
      host.domains = attr[:domains]
      hosts << host
    end

    StackBuilder::Allocator::Hosts.new(:hosts => hosts, :preference_functions => preference_functions)
  end
end
