require 'stacks/namespace'

class Stacks::Environment

  attr_reader :name, :options, :stacks, :stack_procs, :environments

  def initialize(name, options, stack_procs)
    @name = name
    @options = options
    @stack_procs = stack_procs
    @environments = {}
    @stacks = {}
  end

  def env(name, &block)
    environments[name] = Stacks::Environment.new(name, self.options, stack_procs)
    environments[name].instance_eval(&block) unless block.nil?
  end

  def instantiate_stack(stack_name)
    factory = stack_procs[stack_name]
    raise "no stack found '#{stack_name}'" if factory.nil?
    instantiated_stack = factory.call(self)
    stacks[instantiated_stack.name] = instantiated_stack
  end

  def contains_node_of_type?(clazz)
    found = false
    accept do |node|
      found = true if node.kind_of?(clazz)
    end
    return found
  end

  def accept(&block)
    stacks.values.each do |stack|
      stack.accept(&block)
    end

    environments.values.each do |environment|
      environment.accept(&block)
    end
  end
end
