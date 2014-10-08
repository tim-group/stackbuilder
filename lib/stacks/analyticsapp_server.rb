require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::AnalyticsAppServer < Stacks::MachineDef

  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    @data_directory  = false
    super(virtual_service.name + "-" + index)
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def to_enc()
    {
      'role::analyticsapp_server' => {
         'datadir'   => @data_directory,
      }
    }
  end

  def data_size(datadir, size)

    @data_directory = "/mnt/data/#{datadir}"

    storage = {
      '/mnt/data' => {
        :type       => 'data',
        :size       => size,
        :persistent => true,
      }
    }
    modify_storage(storage)

  end

  def create_persistent_storage_override
    modify_storage({
      '/mnt/data' => {
         :persistence_options => { :on_storage_not_found => :create_new }
      }
    })
  end

end

