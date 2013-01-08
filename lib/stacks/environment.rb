require 'stacks/namespace'
require 'stacks/stack'
require 'stacks/machine_def_container'
class Stacks::Environment
  attr_reader :name

  def initialize(name)
   extend Stacks::MachineDefContainer

   @name = name
    @domain = "dev.net.local"
    @definitions = {}
  end

  def loadbalancer(name)
    2.times do |i|
      instance_name = sprintf("%s-%s-%03d", self.name, name, i+1)
      @definitions[instance_name] =  Stacks::LoadBalancer.new(instance_name)
    end
  end

  def virtualservice(name)
    @definitions[name] = Stacks::VirtualService.new(name, self)
  end

end
