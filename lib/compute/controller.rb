require 'support/callback'
require 'support/monkeypatches' # Add flatten_hashes method to Array
require 'compute/namespace'
require 'compute/client'
require 'compute/nagservclient'
require 'socket'
require 'set'

class Compute::Allocation

  def initialize(current_allocation)
    @current_allocation = current_allocation
  end

  def allocate(hosts, specs)
    h = 0
    specs.each do |s|
      host = hosts[h.modulo(hosts.size)]
      @current_allocation[host].nil? ? @current_allocation[host] = []: false
      @current_allocation[host] << s
      h += 1
    end
    @current_allocation
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
        @compute_node_client.audit_host(fabric)
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

        allocation.merge Hash[@compute_node_client.audit_hosts(fabric).map do |key,value|
          active_hosts = !value.nil?? value[:active_hosts] : []
          [key, active_hosts]
        end]

        hosts = @compute_node_client.audit_hosts(fabric).keys.sort
        raise "unable to find any suitable compute nodes" if hosts.empty?

        compute_allocation = Compute::Allocation.new(allocation)
        allocation.merge compute_allocation.allocate(hosts, specs)
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
    grouped_results = allocation.map do |host, specs|
      @compute_node_client.send(selector, host, specs)
    end

    dispatch_results(all_specs, grouped_results, callback)
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

