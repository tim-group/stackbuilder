require 'compute/namespace'
require 'socket'

class Compute::Controller
  def initialize(args = {})
    @compute_node_client = args[:compute_node_client] || Compute::Client.new
    @dns_client = args[:dns_client] || Support::DNS.new
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

  def launch(specs)
    current = Hash[resolve(specs).to_a.select { |hostname, address| !address.nil? }]
    raise "some specified machines already exist: #{current.inspect}" unless current.empty?

    allocation = allocate(specs)

    results = allocation.map do |host, specs|
      @compute_node_client.launch(host, specs)
    end
    return results.flatten
  end

  def clean(specs)
    fabrics = specs.group_by { |spec| spec[:fabric] }
    results = fabrics.map do |fabric, specs|
      @compute_node_client.clean(fabric, specs)
    end
    return results.flatten
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
    mco_client("computenode", :timeout=>120, :hosts=>[host]) do |mco|
      mco.launch(:specs=>specs)
    end
  end

  def clean(fabric, specs)
    mco_client("computenode", :fabric=>fabric) do |mco|
      mco.clean(:specs => specs)
    end
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
