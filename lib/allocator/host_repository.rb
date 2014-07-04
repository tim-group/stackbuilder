require 'allocator/namespace'
require 'allocator/hosts'

class StackBuilder::Allocator::HostRepository
  attr_accessor :machine_repo
  attr_reader :preference_functions
  attr_reader :policies

  def initialize(args)
    @machine_repo = args[:machine_repo]
    @preference_functions = args[:preference_functions]
    @compute_node_client = args[:compute_node_client]
    @policies = args[:policies]
    @logger = args[:logger]
  end

  def find_current(fabric)
    result = @compute_node_client.audit_hosts(fabric)
    hosts = []
    result.each do |fqdn, attr|
      vms = []
      attr[:active_domains].each do |vm_hostname|
        vm_object = machine_repo.find_by_hostname(vm_hostname)
        if vm_object.nil?
          vms << {:hostname => vm_hostname, :in_model => false}
        else
          vms << vm_object.to_spec
        end
      end

      @policies = [] if fabric == "local"

      host = StackBuilder::Allocator::Host.new(fqdn,
        :preference_functions => preference_functions,
        :policies => policies,
        :ram => attr[:memory],
        :lvm => attr[:lvm_vg] #,
#        :storage => attr[:storage]
      )

      host.allocated_machines = vms
      hosts << host
    end

    StackBuilder::Allocator::Hosts.new(:hosts => hosts, :preference_functions => preference_functions, :logger => @logger)
  end
end

