require 'stackbuilder/support/callback'
require 'stackbuilder/support/monkeypatches' # Add flatten_hashes method to Array
require 'stackbuilder/compute/namespace'
require 'stackbuilder/compute/client'
require 'stackbuilder/compute/nagservclient'
require 'socket'
require 'set'

class Compute::Allocation
  def initialize(audit)
    @current_allocation = Hash[audit.map do |key, value|
      active_hosts = !value.nil? ? value[:active_domains] : []
      [key, active_hosts]
    end]
  end

  def create_vm_to_host_map
    ## FIXME: Rubocop - Use flat_map instead of map...flatten.
    Hash[@current_allocation.reject { |_host, vms| vms.nil? }.map do |host, vms|
      vms.map do |vm|
        [vm, host]
      end
    end.flatten(1)]
  end

  def allocate(specs)
    hosts = @current_allocation.keys.sort

    fail "unable to find any suitable compute nodes" if hosts.empty?

    h = 0
    vms_to_host_map = create_vm_to_host_map

    new_allocation = {}

    specs.sort_by { |spec| spec[:hostname] }.each do |spec|
      next if vms_to_host_map.include?(spec[:hostname])

      host = hosts[h.modulo(hosts.size)]
      add_to_allocation(new_allocation, host, spec)
      h += 1
    end

    new_allocation
  end

  private

  def add_to_allocation(new_allocation, host, spec)
    new_allocation[host].nil? ? new_allocation[host] = [] : false
    new_allocation[host] << spec
  end
end

class Compute::Controller
  def initialize(args = {})
    @compute_node_client = args[:compute_node_client] || Compute::Client.new
    @nagsrv_client = Compute::NagsrvClient.new
  end

  def enable_notify(specs)
    specs.each do |spec|
      pp @nagsrv_client.toggle_notify('enable-notify', spec[:qualified_hostnames][:mgmt])
    end
  end

  def disable_notify(specs)
    specs.each do |spec|
      pp @nagsrv_client.toggle_notify('disable-notify', spec[:qualified_hostnames][:mgmt])
    end
  end

  def launch_raw(allocation, &block)
    grouped_results = []

    threads = allocation.map do |ahost, aspecs|
      Thread.new(ahost, aspecs) do |host, specs|
        grouped = {}

        specs.map do |spec|
          result = @compute_node_client.launch(host, [spec])

          result.each do |sender, result_hash|
            result_text = result_hash[spec[:hostname]].nil? ? 'nil' : result_hash[spec[:hostname]].first
            logger(Logger::INFO) { "#{host} launch #{spec[:hostname]} result: #{sender}: #{result_text}" }

            grouped[sender] = {} if grouped[sender].nil?
            grouped[sender].merge!(result_hash)
          end
        end

        final_result = grouped.map do |key, value|
          [key, value]
        end

        grouped_results << final_result
      end
    end

    threads.each(&:join)

    ## FIXME: Rubocop - Use flat_map instead of map...flatten.
    all_specs = allocation.map do |_host, specs|
      specs
    end.flatten

    callback = Support::Callback.new(&block)
    dispatch_results(all_specs, grouped_results, callback)
  end

  # DEP
  def allocate(specs)
    fabrics = specs.group_by { |spec| spec[:fabric] }

    allocation = {}

    fabrics.each do |fabric, fspecs|
      if fabric == "local"
        localhost = Socket.gethostbyname(Socket.gethostname).first
        allocation[localhost] = fspecs
      else
        audit = @compute_node_client.audit_hosts(fabric)
        new_allocation = Compute::Allocation.new(audit).allocate(fspecs)
        allocation = allocation.merge(new_allocation)
      end
    end

    allocation
  end

  def resolve(specs)
    Hash[specs.map do |spec|
      qualified_hostname = spec[:qualified_hostnames][:mgmt]
      [qualified_hostname, @dns_client.gethostbyname(qualified_hostname)]
    end]
  end

  def dispatch_results(all_specs, grouped_results, callback)
    results = grouped_results.flatten_hashes

    flattened_results = results.map do |host, vms|
      vms.map do |vm, result|
        [vm, { :result => result, :host => host }]
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

    allocation.each do |_host, specs|
      allocated_specs << specs
    end

    active_specs = all_specs.to_set - allocated_specs.flatten.to_set

    active_specs.each do |vm|
      callback.invoke :already_active, vm[:hostname]
    end

    grouped_results = allocation.map do |host, aspecs|
      @compute_node_client.send(selector, host, aspecs)
    end

    dispatch_results(allocated_specs.flatten, grouped_results, callback)
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
    non_destroyable_specs, destroyable_specs = all_specs.partition do |spec|
      spec[:disallow_destroy]
    end

    destroyable_spec_results = clean_destroyable_vms(destroyable_specs)

    dispatch_results(destroyable_specs, destroyable_spec_results, callback)

    fail_non_destroyable_vms(non_destroyable_specs, callback)
  end

  def add_cnames(all_specs, &block)
    allocate_and_send(:add_cnames, all_specs, &block)
  end

  def remove_cnames(all_specs, &block)
    allocate_and_send(:remove_cnames, all_specs, &block)
  end

  private

  def clean_destroyable_vms(destroyable_specs)
    fabrics = destroyable_specs.group_by { |spec| spec[:fabric] }
    grouped_results = fabrics.map do |fabric, specs|
      @compute_node_client.clean(fabric, specs)
    end
    grouped_results
  end

  def fail_non_destroyable_vms(non_destroyable_specs, _callback)
    non_destroyable_specs.each do |spec|
      logger(Logger::FATAL) do
        "#{spec[:hostname]} is not destroyable\n To override this protection, " \
        "please specify machine.destroyable = true"
      end
      fail "#{spec[:hostname]} is not destroyable"
    end
  end
end
