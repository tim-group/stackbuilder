require 'stacks/namespace'
require 'stacks/stack'

class Stacks::Environment
  attr_accessor :registry
  attr_reader :name
  attr_accessor :stack_templates
  attr_accessor :domain
  attr_reader :stacks

  def initialize(name, parent=nil)
    @name = name
    @parent = parent
    @domain = "dev.net.local"
    @stacks = {}
    @registry = {}
    @sub_environments = {}
  end

  def stack(name, &block)
    if (stack_templates[name])
      stack = stack_templates[name].call()
    else
      stack = Stacks::Stack.new(name)
    end
    stack.instance_eval(&block) unless block.nil?
    @stacks[name] = stack
    return stack
  end

  def generate()
    @stacks.values.each do |stack|
      stack.generate(self)
    end
    @sub_environments.values.each do |env|
      env.generate()
    end
  end

  def collapse_registries
    registry = self.registry
    @sub_environments.values.each do |env|
      registry = registry.merge(env.registry)
    end
    registry = registry.reject do |k,v| v.kind_of?(Stacks::VirtualService) end
    return registry
  end

  def lookup(ident)
    raise "unable to find object with ident #{ident}" unless registry[ident]
    return registry[ident]
  end

  def env(name, &block)
    @sub_environments[name] = env = Stacks::Environment.new(name, self)
    env.stack_templates = self.stack_templates
    env.instance_eval(&block)
    return env
  end
end
