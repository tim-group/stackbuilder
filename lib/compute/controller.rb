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
      qualified_hostname = spec[:qualified_hostnames]['mgmt']
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

require 'mcollective'
require 'support/mcollective'

class Compute::Client
  include Support::MCollective

  def find_hosts(fabric)
    mco_client("computenode", :fabric => fabric) do |mco|
      mco.discover.sort()
    end
  end

  def invoke(selector, specs, client_options)
    mco_client("computenode", client_options) do |mco|
      mco.send(selector, :specs => specs).map do |node|
        if node[:statuscode] != 0
          raise node[:statusmsg]
        end
        [node.results[:sender], node.results[:data]]
      end
    end
  end

  def launch(host, specs)
    invoke :launch, specs, :timeout => 1000, :nodes => [host]
  end

  def allocate_ips(host, specs)
    invoke :allocate_ips, specs, :nodes => [host]
  end

  def free_ips(host, specs)
    invoke :free_ips, specs, :nodes => [host]
  end

  def clean(fabric, specs)
    invoke :clean, specs, :fabric => fabric
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
