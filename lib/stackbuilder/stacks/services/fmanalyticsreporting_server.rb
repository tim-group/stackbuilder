require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::FmAnalyticsReportingServer < Stacks::MachineDef
  def to_enc
    enc = super()
    enc.merge!('role::fmanalyticsreporting_server' => {})
    enc
  end
end
