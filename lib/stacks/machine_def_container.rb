require 'stacks/namespace'

class Stacks::MachineDefContainer
  attr_reader :definitions

  def initialize()
    @definitions = {}
  end

  def children
    # pretend we have a sorted dictionary
    return @definitions.sort.map do |k, v| v end
  end

  def accept(&block)
    block.call(self)
    children.each do |child|
      child.accept(&block)
    end
  end

  def bind_to(environment)
    children.each do |child|
      child.bind_to(environment)
    end
  end

  def machines
    return_machines = []
    @definitions.each do |name, machine_def|
      return_machines |= machine_def.machines
    end
    return return_machines
  end

  def recursive_extend(extended_module)
    self.extend(extended_module)
    self.children.each do |child|
      child.recursive_extend(extended_module)
    end
  end

  def clazz
    return "container"
  end

  def to_specs
    return self.children.map do |child|
      child.to_specs
    end.flatten
  end

end
