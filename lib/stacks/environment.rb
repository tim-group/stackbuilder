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

  def instantiate_stack(stack)
    stack = stack_procs[stack].call(self)
    stacks[stack.name] = stack
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
