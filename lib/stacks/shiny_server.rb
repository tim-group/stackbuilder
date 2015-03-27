require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::ShinyServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    {
      'role::shiny_server' => {}
    }
  end
end
