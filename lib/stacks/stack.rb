require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/virtual_service'
require 'stacks/loadbalancer'
require 'stacks/nat_server'

class Stacks::Stack < Stacks::MachineDefContainer
  attr_reader :name

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def virtualservice(name, &block)
    @definitions[name] = virtualservice = Stacks::VirtualService.new(name)
    virtualservice.instance_eval(&block) unless block.nil?
  end

  def loadbalancer(options={:instances=>2})
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      hostname = "lb-#{index}"
      @definitions[hostname] = Stacks::LoadBalancer.new(hostname)
    end
  end

  def natserver
    @definitions["nat-001"] = Stacks::NatServer.new("nat-001")
  end

  def [](key)
    return @definitions[key]
  end

end
