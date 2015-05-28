require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::StandardServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    {
      'server::default_new_mgmt_net_local' => {}
    }
  end
end
