require 'stacks/namespace'
require 'stacks/load_balancer'

class Stacks::LoadBalancerDefinition
  attr_reader :name
  def initialize(name)
    @name = name
    @times = 2
  end

  def generate(env)
    @times.times do |i|
      name = sprintf("%s-%s-%03d", env.name, self.name, i+1)
      env.registry[name] = Stacks::LoadBalancer.new(name)
    end
  end
end