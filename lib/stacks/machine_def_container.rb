require 'stacks/namespace'

class Stacks::MachineDefContainer
  attr_reader :definitions

  def initialize()
    @definitions = {}
  end

  def children
    return @definitions.values
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

  def rspecs
    return []
  end

end
