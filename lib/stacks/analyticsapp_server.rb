require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::AnalyticsAppServer < Stacks::MachineDef

  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def to_enc()
    {
      'role::analyticsapp_server' => {
         'datadir'   => '/mnt/data/finmet',
      }
    }
  end

  def data_size(size)
    modify_storage({'/mnt/data' => { :size => size }})
  end

  def create_persistent_storage_override
    modify_storage({
      '/mnt/data' => {
         :persistence_options => { :on_storage_not_found => :create_new }
      }
    })
  end

end

