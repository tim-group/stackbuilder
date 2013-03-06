require 'stacks/namespace'

class Stacks::Environment
  attr_reader :name, :options

  def initialize(name, options, stack_procs)
    @name = name
    @options = options
    @stack_procs = stack_procs
    @machine_def_containers = {}
  end

  def [](key)
    return @machine_def_containers[key]
  end

  def env(name, &block)
    @machine_def_containers[name] = Stacks::Environment.new(name, self.options, @stack_procs)
    @machine_def_containers[name].instance_eval(&block) unless block.nil?
  end

  def instantiate_stack(stack_name)
    factory = @stack_procs[stack_name]
    raise "no stack found '#{stack_name}'" if factory.nil?
    instantiated_stack = factory.call(self)
    @machine_def_containers[instantiated_stack.name] = instantiated_stack
  end

  def contains_node_of_type?(clazz)
    found = false
    accept do |node|
      found = true if node.kind_of?(clazz)
    end
    return found
  end

  def accept(&block)
    @machine_def_containers.values.each do |machine_def|
      machine_def.accept(&block)
    end
  end
end
