require 'stacks/namespace'

class Stacks::MachineDef
  attr_reader :hostname, :domain

  def initialize(hostname)
    @hostname = hostname
  end

  def name
    return @hostname
  end

  def children
    return []
  end

  def accept(&block)
    block.call(self)
  end

  def bind_to(environment)
  end

  def machines
    return [self]
  end

  def recursive_extend(extended_module)
    self.extend(extended_module)
  end

  def to_specs
    return []
  end

  def clazz
    return "machine"
  end

end
