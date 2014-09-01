require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::MysqlDBServer < Stacks::MachineDef

  attr_accessor :database_name, :application
  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
    storage = {
      '/mnt/data' => {
        :type                => 'data',
        :size                => '10G',
        :persistent          => true,
        :persistence_options => {
          :on_storage_not_found => :raise_error
        }
      }
    }
    modify_storage(storage)
    @ram = '4194304' # 4GB
    @vcpus = '2'
    @destroyable = false
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def to_enc()
    enc = {
      'role::databaseserver' => {
        'application'              => @virtual_service.application,
        'environment'              => environment.name,
        'database_name'            => @virtual_service.database_name,
        'restart_on_config_change' => false,
        'restart_on_install'       => true,
      }
    }

    if @virtual_service.dependant_instances and ! @virtual_service.dependant_instances.nil? and @virtual_service.dependant_instances != []
      enc['role::databaseserver'].merge!({
        'dependencies' => @virtual_service.dependency_config,
        'dependant_instances' => @virtual_service.dependant_instances,
      })
    end

    enc
  end

end

