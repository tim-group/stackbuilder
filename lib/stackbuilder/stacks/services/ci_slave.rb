require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Services::CiSlave < Stacks::MachineDef
  def initialize(server_group, index)
    super(server_group.name + "-" + index, [:mgmt])
    self
  end

  def availability_group
    nil
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
