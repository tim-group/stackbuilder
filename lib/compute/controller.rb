require 'support/callback'
require 'compute/namespace'
require 'socket'
require 'set'

class Array
  def flatten_hashes
    Hash[*self.map(&:to_a).flatten]
  end
end

class Compute::Controller
  def initialize(args = {})
    @compute_node_client = args[:compute_node_client] || Compute::Client.new
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

  def allocate(specs)
    specs.each do |spec|
      spec[:spindle] = "/var/local/images/"
    end

    fabrics = specs.group_by { |spec| spec[:fabric] }

    allocation = {}

    fabrics.each do |fabric, specs|
      if fabric == "local"
        localhost =  Socket.gethostbyname(Socket.gethostname).first
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
      qualified_hostname = spec[:qualified_hostnames]['mgmt']
      [qualified_hostname, @dns_client.gethostbyname(qualified_hostname)]
    end]
  end

  def launch(all_specs, &block)
    #current = Hash[resolve(specs).to_a.select { |hostname, address| !address.nil? }]
    #    raise "some specified machines already exist: #{current.inspect}" unless current.empty?

    callback = Support::Callback.new
    callback.instance_eval(&block)
    allocation = allocate(all_specs)

    results = allocation.map do |host, specs|
      @compute_node_client.launch(host, specs)
    end.flatten_hashes

    flattened_results = results.map do |host, vms|
      vms.map do |vm, result|
        [vm, {:result=>result, :host=>host}]
      end
    end.flatten_hashes

    all_specs.each do |spec|
      vm = spec[:hostname]
      result = flattened_results[vm]
      if result.nil?
        callback.invoke :unaccounted, vm
        next
      end
      if result[:result] == "success"
        callback.invoke :success, vm
      else
        callback.invoke :failure, vm
      end
    end

    callback.invoke :hasfailures, all_specs, :if=>[:failure]
  end

  def allocate_ips(all_specs, &block)
    callback = Support::Callback.new
    callback.instance_eval(&block)
    allocation = allocate(all_specs)

    results = allocation.map do |host, specs|
      @compute_node_client.allocate_ips(host, specs)
    end.flatten_hashes

    flattened_results = results.map do |host, vms|
      vms.map do |vm, result|
        [vm, {:result=>result, :host=>host}]
      end
    end.flatten_hashes

    all_specs.each do |spec|
      vm = spec[:hostname]
      result = flattened_results[vm]
      if result.nil?
        callback.invoke :unaccounted, vm
        next
      end
      if result[:result] == "success"
        callback.invoke :success, vm
      else
        callback.invoke :failure, vm
      end
    end

    callback.invoke :hasfailures, all_specs, :if=>[:failure]
  end

  def free_ips(all_specs, &block)
    callback = Support::Callback.new
    callback.instance_eval(&block)
    allocation = allocate(all_specs)

    results = allocation.map do |host, specs|
      @compute_node_client.free_ips(host, specs)
    end.flatten_hashes

    flattened_results = results.map do |host, vms|
      vms.map do |vm, result|
        [vm, {:result=>result, :host=>host}]
      end
    end.flatten_hashes

    all_specs.each do |spec|
      vm = spec[:hostname]
      result = flattened_results[vm]
      if result.nil?
        callback.invoke :unaccounted, vm
        next
      end
      if result[:result] == "success"
        callback.invoke :success, vm
      else
        callback.invoke :failure, vm
      end
    end

    callback.invoke :hasfailures, all_specs, :if=>[:failure]
  end

  def clean(specs, &block)
    callback = Support::Callback.new
    unless block.nil?
      callback.instance_eval(&block)
    end

    fabrics = specs.group_by { |spec| spec[:fabric] }
    vm_counts = {}
    results = fabrics.map do |fabric, specs|
      @compute_node_client.clean(fabric, specs)
    end.flatten_hashes

    flattened_results = results.map do |host, vms|
      vms.map do |vm, result|
        [vm, {:result=>result, :host=>host}]
      end
    end.flatten_hashes

    vms_asked_for = specs.each do |spec|
      vm = spec[:hostname]
      result = flattened_results[vm]
      if result.nil?
        callback.invoke :unaccounted, vm
        next
      end
      if result[:result] == "success"
        callback.invoke :success, vm
      else
        callback.invoke :failure, vm
      end
    end
    array_failures = results.map do |host, vms|
      vms.map do |node, result|
        result
      end
    end.flatten

    vms_accounted_for = results.map do |host, vms|
      vms.map do |vm, result|
        vm
      end
    end.flatten

    vms_asked_for = specs.map do |spec|
      spec[:hostname]
    end

    unaccounted_vms = vms_asked_for.to_set - vms_accounted_for.to_set
    if unaccounted_vms.size >0
      @logger.warn("some vms were unaccounted for #{unaccounted_vms.inspect}")
    end
    results
  end

end

require 'mcollective'
require 'support/mcollective'

class Compute::Client
  include Support::MCollective

  def find_hosts(fabric)
    mco_client("computenode", :fabric=>fabric) do |mco|
      mco.discover.sort()
    end
  end

  def launch(host, specs)
    mco_client("computenode", :timeout=>1000, :nodes=>[host]) do |mco|
      mco.launch(:specs=>specs).map do |node|
        if node[:statuscode]!=0
          raise node[:statusmsg]
        end
        [node.results[:sender], node.results[:data]]
      end
    end
  end

  def allocate_ips(host, specs)
    mco_client("computenode", :timeout=>1000, :nodes=>[host]) do |mco|
      mco.allocate_ips(:specs=>specs).map do |node|
        if node[:statuscode]!=0
          raise node[:statusmsg]
        end
        [node.results[:sender], node.results[:data]]
      end
    end
  end

  def free_ips(host, specs)
    mco_client("computenode", :timeout=>1000, :nodes=>[host]) do |mco|
      mco.free_ips(:specs=>specs).map do |node|
        if node[:statuscode]!=0
          raise node[:statusmsg]
        end
        [node.results[:sender], node.results[:data]]
      end
    end
  end

  def clean(fabric, specs)
    results = mco_client("computenode", :fabric=>fabric) do |mco|
      mco.clean(:specs => specs).map do |node|
        if node[:statuscode]!=0
          raise node[:statusmsg]
        end
        [node.results[:sender], node.results[:data]]
      end
    end
    Hash[*results.flatten]
  end
end

require 'socket'
require 'ipaddr'

class Support::DNS
  # returns nil if lookup fails, but propagates any errors in formatting
  def gethostbyname(hostname)
    begin
      addrinfo = Socket.gethostbyname(hostname)
    rescue
      return nil
    end
    return IPAddr.ntop(addrinfo[3])
  end
end
