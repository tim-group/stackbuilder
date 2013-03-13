require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/virtual_service'
require 'stacks/loadbalancer'
require 'stacks/nat_server'
require 'stacks/proxy_server'

class Stacks::Stack < Stacks::MachineDefContainer
  attr_reader :name

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def virtual_appserver(name, &block)
    @definitions[name] = virtualservice = Stacks::VirtualService.new(name, :AppServer)
    virtualservice.instance_eval(&block) unless block.nil?
  end

  def virtual_proxyserver(name, &block)
    @definitions[name] = virtualservice = Stacks::VirtualService.new(name, :ProxyServer, &block)
  end

  def loadbalancer(options={:instances=>2})
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      hostname = "lb-#{index}"
      @definitions[hostname] = Stacks::LoadBalancer.new(hostname)
    end
  end

  def natserver(options={:instances=>2})
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      hostname = "nat-#{index}"
      @definitions[hostname] = Stacks::NatServer.new(hostname)
    end
  end

  def [](key)
    return @definitions[key]
  end

end
