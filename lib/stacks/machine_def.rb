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

  def visit(arg, &block)
    block.call(arg, self, block)
  end

  def to_spec
    return {}
  end
end
