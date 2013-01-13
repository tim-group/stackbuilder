require 'stacks/namespace'

class Stacks::MachineDef
  attr_reader :hostname

  def initialize(hostname)
    @hostname = hostname
  end

  def name
    return @hostname
  end

  def children
    return []
  end

  def machines
    return [self]
  end

  def recursive_extend(extended_module)
    self.extend(extended_module)
  end

  def to_spec
    return {}
  end

  def clazz
    return "machine"
  end
end
