require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::CiSlave < Stacks::MachineDef
  def initialize(server_group, index, &block)
    super(server_group.name + "-" + index, [:mgmt, :prod, :front])
    self
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    {
      'role::cinode_precise' => {}
    }
  end
end

