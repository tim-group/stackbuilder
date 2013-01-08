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

  def visit(arg, &block)
    block.call(arg, self)
  end

  def to_spec
    return {}
  end
end
