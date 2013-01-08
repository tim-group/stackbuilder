require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::LoadBalancer < Stacks::MachineDef
  def initialize(hostname)
    super(hostname)
  end

  def to_tree
    {}
  end

  def to_spec
    spec = super
    return spec
  end
end
