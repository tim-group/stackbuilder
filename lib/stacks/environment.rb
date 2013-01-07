require 'stacks/namespace'
require 'stacks/stack'

class Stacks::Environment
  attr_reader :name

  def initialize(name)
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
    2.times do |i|
      app_server_name = sprintf("%s-%s-%03d", self.name, name, i+1)
      @definitions[app_server_name] = Stacks::Server.new(app_server_name, name)
    end
  end

  def generate

  end

  def machines
    return @definitions.values
  end
end
