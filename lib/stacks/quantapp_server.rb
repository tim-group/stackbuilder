require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::QuantAppServer < Stacks::MachineDef

  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_spec
    spec = super
    spec
  end

  def to_enc()
    {
      'role::quantapp_server' => {}
    }
  end
end
