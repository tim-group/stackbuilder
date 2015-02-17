require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::LegacyMysqlDBServer < Stacks::MachineDef

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


  def to_enc()
    enc = {
      'role::databaseserver' => {
        'environment'              => environment.name,
        'application'              => @virtual_service.application,
        'database_name'            => @virtual_service.database_name,
        'restart_on_config_change' => false,
        'restart_on_install'       => true,
        'datadir'                  => '/mnt/data/mysql'
      }
    }
    dependant_instances = @virtual_service.dependant_machine_def_fqdns
    if dependant_instances and ! dependant_instances.nil? and dependant_instances != []
      enc['role::databaseserver'].merge!({
        'dependencies' => @virtual_service.dependency_config,
        'dependant_instances' => dependant_instances,
      })
      enc.merge!(@virtual_service.dependant_instance_mysql_rights)
    end
    enc
  end

end
