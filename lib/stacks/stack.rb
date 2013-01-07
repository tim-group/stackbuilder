require 'stacks/namespace'
require 'stacks/load_balancer_definition'
require 'stacks/virtual_service_definition'
require 'stacks/puppetmaster_definition'

class Stacks::Stack
  attr_reader :name
  attr_reader :env

  def initialize(name, env)
    @name = name
    @loadbalancers = []
    @definitions = []
    @env = env
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
    2.times do |i|
      name = sprintf("%s-%s-%03d", env.name, self.name, i+1)
      @definitions << Stacks::LoadBalancer.new(name,self)
    end
  end

  def generate(env)
    @definitions.each do |definition|
      definition.generate(env)
    end
  end

  def machines
    machines = {}
    @definitions.each do |definition|
      machines = machines.merge definition.machines
    end

    return machines
  end

end
