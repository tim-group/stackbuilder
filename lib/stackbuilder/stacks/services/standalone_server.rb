require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::StandaloneServer < Stacks::MachineDef
  attr_reader :environment

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super()
    spec.delete(:availability_group)
    spec
  end
end
