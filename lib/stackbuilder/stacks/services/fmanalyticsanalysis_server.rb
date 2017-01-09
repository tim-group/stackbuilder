require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::FmAnalyticsAnalysisServer < Stacks::MachineDef
  def to_enc
    enc = super()
    enc.merge!('role::fmanalyticsanalysis_server' => {
                 'datadir'     => false,
                 'environment' => environment.name
               }, 'role::shiny_server' => {})

    enc
  end
end
