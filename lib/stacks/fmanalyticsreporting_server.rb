require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::FmAnalyticsReportingServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    {
      'role::fmanalyticsreporting_server' => {}
    }
  end
end
