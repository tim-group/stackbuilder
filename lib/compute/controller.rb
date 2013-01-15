require 'compute/namespace'

class Compute::Controller
  def initialize(args = {})
    @compute_node_client = args[:compute_node_client] || ComputeNodeClient.new
  end

  def allocate(specs)
    puts "allocating virtual machines to hosts"

    specs.each do |spec|
        spec[:spindle] = "/var/local/images/"
    end

    fabrics = specs.group_by { |spec| spec[:fabric] }

    allocation = {}

    fabrics.each do |fabric, specs|
      if fabric == "local"
        localhost = `hostname --fqdn`.chomp
        allocation[localhost] = specs
      else
        hosts = @compute_node_client.find_hosts(fabric)
        raise "unable to find any suitable compute nodes" if hosts.empty?
        host = hosts[0]
        allocation[host] = specs
      end
    end

    return allocation
  end

  def launch(specs)
    allocation = allocate(specs)

    allocation.each do |host, specs|
      @compute_node_client.launch(host, specs)
    end
  end
end

require 'mcollective'
require 'stacks/mcollective/support'

class ComputeNodeClient
  include Stacks::MCollective::Support
  include MCollective::RPC

  def find_hosts(fabric)
    return mcollective_fabric do
      mco = rpcclient("computenode")
#      mco.identity_filter /\.mgmt\.#{fabric}\.net\.local$/
      mco.fact_filter "domain","mgmt.#{fabric}.net.local"
      hosts = mco.discover()
      mco.disconnect
      hosts.sort
    end
  end

  def launch(host, specs)
    result = mcollective_fabric do
      options = MCollective::Util.default_options
      options[:timeout] = 120
      mco = rpcclient("computenode", :options=>options)
      mco.discover(:hosts => [host])

      pp host
      results = mco.launch(:specs=>specs)
      mco.disconnect
      results
    end

    pp result
  end
end
