require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::StandardServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    return {
      'server::default_new_mgmt_net_local' => {}
    }
  end
end
