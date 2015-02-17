require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::FmAnalyticsAppServer < Stacks::MachineDef

  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc()
    {
      'role::fmanalyticsapp_server' => {}
    }
  end
end
