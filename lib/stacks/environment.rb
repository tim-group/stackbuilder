require 'stacks/namespace'
require 'stacks/machine_def_container'

class Stacks::Environment
  attr_reader :name, :options

  include Stacks::MachineDefContainer

  def initialize(name, options, stack_procs)
    @name = name
    @options = options
    @stack_procs = stack_procs
    @definitions = {}
    @persistent_storage_supported = options[:persistent_storage_supported].nil? ? true : options[:persistent_storage_supported]
    @every_machine_destroyable = options[:every_machine_destroyable].nil? ? false : options[:every_machine_destroyable]
  end

  def environment
    return self
  end

  def persistent_storage_supported?
     @persistent_storage_supported
  end

  def every_machine_destroyable?
    @every_machine_destroyable
  end

  def env(name, options={}, &block)
    @definitions[name] = Stacks::Environment.new(name, self.options.merge(options), @stack_procs)
    @definitions[name].instance_eval(&block) unless block.nil?
  end

  def instantiate_stack(stack_name)
    factory = @stack_procs[stack_name]
    raise "no stack found '#{stack_name}'" if factory.nil?
    instantiated_stack = factory.call(self)
    @definitions[instantiated_stack.name] = instantiated_stack
  end

  def contains_node_of_type?(clazz)
    found = false
    accept do |node|
      found = true if node.kind_of?(clazz)
    end
    return found
  end
end

