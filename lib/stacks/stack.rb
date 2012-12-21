require 'stacks/namespace'
require 'stacks/load_balancer_definition'
require 'stacks/virtual_service_definition'
require 'stacks/puppetmaster_definition'

class Stacks::Stack
  attr_reader :name
  def initialize(name)
    @name = name
    @loadbalancers = []
    @definitions = []
  end

  def puppetmaster(name="puppetmaster", &block)
    @definitions << puppetmasterdefinition = Stacks::PuppetMasterDefinition.new(name)
    return puppetmasterdefinition
  end

  def virtualservice(name, options={:type=>:appserver}, &block)
    @definitions << virtualservicedefinition = Stacks::VirtualServiceDefinition.new(name,options)
    virtualservicedefinition.instance_eval(&block) if block != nil
    return virtualservicedefinition
  end

  def loadbalancer(name, &block)
    @definitions << loadbalancerdefinition = Stacks::LoadBalancerDefinition.new(name)
    loadbalancerdefinition.instance_eval(&block) if block != nil
    return loadbalancerdefinition
  end

  def generate(env)
    stack_registry = {}
    @definitions.each do |definition|
      stack_registry = stack_registry.merge(definition.generate(env))
    end

    return stack_registry
  end
end

