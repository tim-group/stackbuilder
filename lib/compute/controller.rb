require 'compute/namespace'

class Compute::Controller
  def initialize(args = {})
    @compute_node_client = args[:compute_node_client] || ComputeNodeClient.new
  end

  def allocate(specs)
    puts "allocating virtual machines to hosts"
    hosts = @compute_node_client.find_hosts()

    raise "unable to find any suitable compute nodes" if hosts.empty?

    host = hosts[0]
    return Hash[specs.map { |spec| [spec[:hostname], host] }]
  end

  def launch(specs)
    puts "launching some stuff"
    pp specs
  end
end

require 'mcollective'
class ComputeNodeClient
  include MCollective::RPC

  def find_hosts()
    mco = rpcclient("computenode")
    hosts = mco.discover()
    mco.disconnect
    return hosts
  end
end
