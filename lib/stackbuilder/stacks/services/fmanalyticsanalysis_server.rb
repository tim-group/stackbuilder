require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::FmAnalyticsAnalysisServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    @data_directory  = false
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    enc = super()
    enc.merge!('role::fmanalyticsanalysis_server' => {
                 'datadir'     => @data_directory,
                 'environment' => environment.name
               })
    enc
  end
end
