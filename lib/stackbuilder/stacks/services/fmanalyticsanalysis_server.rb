require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::FmAnalyticsAnalysisServer < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    @data_directory  = false
    super(virtual_service.name + "-" + index)
  end

  def to_enc
    {
      'role::fmanalyticsanalysis_server' => {
        'datadir'     => @data_directory,
        'environment' => environment.name,
      },
    }
  end

  def persistent_storage(datadir, size)
    @data_directory = datadir

    storage = {
      '/mnt/data' => {
        :type                => 'data',
        :size                => size,
        :persistent          => true,
        :persistence_options => { :on_storage_not_found => :create_new },
      },
    }
    modify_storage(storage)
  end
end
