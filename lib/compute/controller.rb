require 'compute/namespace'

class Compute::Controller
  def initialize(args = {})
    @compute_node_client = args[:compute_node_client] || ComputeNodeClient.new
  end

  def allocate(specs)
    puts "allocating virtual machines to hosts"

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
    puts "launching some stuff"
    pp specs
  end
end

require 'mcollective'
class ComputeNodeClient
  include MCollective::RPC

  def find_hosts(fabric)
    mco = rpcclient("computenode")
    hosts = mco.discover()
    mco.disconnect
    return hosts
  end
end
