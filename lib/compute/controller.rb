require 'support/callback'
require 'support/monkeypatches' # Add flatten_hashes method to Array
require 'compute/namespace'
require 'compute/client'
require 'compute/nagservclient'
require 'support/dns'
require 'socket'
require 'set'

class Compute::Controller
  def initialize(args = {})
    @compute_node_client = args[:compute_node_client] || Compute::Client.new
    @nagsrv_client = Compute::NagsrvClient.new
    @dns_client = args[:dns_client] || Support::DNS.new
    @logger = args[:logger] || Logger.new(STDOUT)
  end

  def allocate_specs_by_rr(hosts, specs, allocation)
    h = 0
    specs.each do |s|
      host = hosts[h.modulo(hosts.size)]
      allocation[host].nil? ? allocation[host] = []: false
      allocation[host] << s
      h += 1
    end
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

  def allocate(specs)
    fabrics = specs.group_by { |spec| spec[:fabric] }

    allocation = {}

    fabrics.each do |fabric, specs|
      if fabric == "local"
        localhost = Socket.gethostbyname(Socket.gethostname).first
        allocation[localhost] = specs
      else
        hosts = @compute_node_client.find_hosts(fabric)
        raise "unable to find any suitable compute nodes" if hosts.empty?
        allocate_specs_by_rr(hosts, specs, allocation)
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
    current = Hash[resolve(all_specs).to_a.select { |hostname, address| !address.nil? }]
    raise "some specified machines already exist: #{current.inspect}" unless current.empty?

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

