require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Services::LegacyMysqlDBServer < Stacks::MachineDef
  attr_accessor :version

  def initialize(virtual_service, index)
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
    @version = '5.1.49-1ubuntu8'
  end

  def to_enc
    enc = {
      'role::databaseserver' => {
        'environment'              => environment.name,
        'application'              => @virtual_service.application,
        'database_name'            => @virtual_service.database_name,
        'restart_on_config_change' => false,
        'restart_on_install'       => true,
        'datadir'                  => '/mnt/data/mysql',
        'version'                  => @version
      }
    }
    dependant_instances = @virtual_service.dependant_machine_def_fqdns(location)
    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::databaseserver'].merge!('dependencies' => @virtual_service.dependency_config(location),
                                         'dependant_instances' => dependant_instances)
      enc.merge!(@virtual_service.dependant_instance_mysql_rights)
    end
    enc
  end
end
