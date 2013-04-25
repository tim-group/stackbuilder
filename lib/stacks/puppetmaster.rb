require 'stacks/namespace'

class Stacks::PuppetMaster < Stacks::MachineDef

  def initialize(base_hostname)
    super(base_hostname, [:mgmt])
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
  end
end
