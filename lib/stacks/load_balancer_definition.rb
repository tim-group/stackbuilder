require 'stacks/namespace'
require 'stacks/load_balancer'

class Stacks::LoadBalancerDefinition
  attr_reader :name
  attr_reader :machines

  def initialize(name)
    @name = name
    @times = 2
    @machines = {}
  end

  def generate(env)
    @times.times do |i|
      name = sprintf("%s-%s-%03d", env.name, self.name, i+1)
      machines[name] = Stacks::LoadBalancer.new(name, env)
    end
  end
end
