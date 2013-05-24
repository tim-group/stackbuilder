require 'support/callback'
require 'support/monkeypatches' # Add flatten_hashes method to Array
require 'compute/namespace'
require 'compute/client'
require 'compute/nagservclient'
require 'socket'
require 'set'

class Compute::Allocation
  def initialize(audit)
    @current_allocation = Hash[audit.map do |key,value|
      active_hosts = !value.nil?? value[:active_domains] : []
      [key, active_hosts]
    end]
  end

  def create_vm_to_host_map
    Hash[@current_allocation.reject { |host,vms| vms.nil? }.map do |host, vms|
      vms.map do |vm|
        [vm, host]
      end
    end.flatten(1)]
  end

  def allocate(specs)
    hosts = @current_allocation.keys.sort

    raise "unable to find any suitable compute nodes" if hosts.empty?

    h = 0
    vms_to_host_map = create_vm_to_host_map

    new_allocation = {}

    specs.sort_by {|spec|spec[:hostname]}.each do |spec|
      unless (vms_to_host_map.include?(spec[:hostname]))
        host = hosts[h.modulo(hosts.size)]
        add_to_allocation(new_allocation, host, spec)
       h += 1
      end
    end

    new_allocation
  end

  private
  def add_to_allocation(new_allocation, host, spec)
    new_allocation[host].nil? ? new_allocation[host] = []: false
    new_allocation[host] << spec
  end
end

class Compute::Controller
  def initialize(args = {})
    @compute_node_client = args[:compute_node_client] || Compute::Client.new
    @nagsrv_client = Compute::NagsrvClient.new
    @logger = args[:logger] || Logger.new(STDOUT)
  end

  def enable_notify(specs)
    specs.each do |spec|
      pp @nagsrv_client.toggle_notify('enable-notify',spec[:qualified_hostnames][:mgmt])
    end
  end

  def disable_notify(specs)
    specs.each do |spec|
      pp @nagsrv_client.toggle_notify('disable-notify',spec[:qualified_hostnames][:mgmt])
    end
  end

  def audit(specs)
    fabrics = specs.group_by { |spec| spec[:fabric] }

    fabrics.each do |fabric, specs|
      pp @compute_node_client.audit_hosts(fabric)
    end
  end

  def allocate(specs)
    fabrics = specs.group_by { |spec| spec[:fabric] }

    allocation = {}

    fabrics.each do |fabric, specs|
      if fabric == "local"
        localhost = Socket.gethostbyname(Socket.gethostname).first
        allocation[localhost] = specs
      else
        audit = @compute_node_client.audit_hosts(fabric)
        new_allocation = Compute::Allocation.new(audit).allocate(specs)
        allocation = allocation.merge(new_allocation)
      end
    end

    return allocation
  end

  def resolve(specs)
    return Hash[specs.map do |spec|
      qualified_hostname = spec[:qualified_hostnames][:mgmt]
      [qualified_hostname, @dns_client.gethostbyname(qualified_hostname)]
    end]
  end

  def dispatch_results(all_specs, grouped_results, callback)
    results = grouped_results.flatten_hashes

    flattened_results = results.map do |host, vms|
      vms.map do |vm, result|
        [vm, {:result => result, :host => host}]
      end
    end.flatten_hashes

    all_specs.each do |spec|
      vm = spec[:hostname]
      result = flattened_results[vm]
      if result.nil?
        callback.invoke :unaccounted, vm
      else
        unpacked_result = result[:result]
        # check for string to tolerate old-fashioned agents, backward compatibility yo
        state, msg = unpacked_result.is_a?(String) ? [unpacked_result, unpacked_result] : unpacked_result
        if state == "success"
          callback.invoke :success, [vm, msg]
        else
          callback.invoke :failure, [vm, msg]
        end
      end
    end

    callback.finish
  end

  def allocate_and_send(selector, all_specs, &block)
    callback = Support::Callback.new(&block)

    allocation = allocate(all_specs)
    allocation.each do |host, vms|
      vms.each do |vm|
        callback.invoke :allocated, [vm[:hostname], host]
      end
    end

    allocated_specs = []

    allocation.each do |host, specs|
      allocated_specs << specs
    end

    active_specs = all_specs.to_set - allocated_specs.flatten.to_set

    active_specs.each do |vm|
      callback.invoke :already_active, vm[:hostname]
    end

    grouped_results = allocation.map do |host, allocated_specs|
      @compute_node_client.send(selector, host, allocated_specs)
    end

    dispatch_results(allocated_specs, grouped_results, callback)
  end

  def launch(all_specs, &block)
    allocate_and_send(:launch, all_specs, &block)
  end

  def allocate_ips(all_specs, &block)
    allocate_and_send(:allocate_ips, all_specs, &block)
  end

  def free_ips(all_specs, &block)
    allocate_and_send(:free_ips, all_specs, &block)
  end

  def clean(all_specs, &block)
    callback = Support::Callback.new(&block)

    fabrics = all_specs.group_by { |spec| spec[:fabric] }
    grouped_results = fabrics.map do |fabric, specs|
      @compute_node_client.clean(fabric, specs)
    end

    dispatch_results(all_specs, grouped_results, callback)
  end

end

