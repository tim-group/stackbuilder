require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::QuantAppServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_spec
    spec = super
    spec
  end

  def to_enc
    enc = super()
    enc.merge!('role::quantapp_server' => {})
    enc
  end
end
