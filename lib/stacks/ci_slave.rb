require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::CiSlave < Stacks::MachineDef
  def bind_to(environment)
    super(environment)
  end

  def to_enc
    {
      'role::cinode_precise' => {}
    }
  end
end

