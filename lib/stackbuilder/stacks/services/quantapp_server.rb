require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::QuantAppServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    {
      'role::quantapp_server' => {
        'allowed_hosts' => @virtual_service.allowed_hosts,
        'environment'   => environment.name
      }
    }
  end
end
