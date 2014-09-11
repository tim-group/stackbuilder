require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::MysqlServer < Stacks::MachineDef

  attr_reader :name
  attr_accessor :master

  def initialize(virtual_service, role, index, &block)
    @virtual_service = virtual_service
    if role == :backup
      @name = "#{virtual_service.name}#{role.to_s}-#{index}"
    else
      @name = "#{virtual_service.name}-#{index}"
    end

    super(@name)
    storage = {
      '/mnt/data' => {
        :type       => 'data',
        :size       => '10G',
        :persistent => true,
      }
    }
    modify_storage(storage)
    @ram = '4194304' # 4GB
    @vcpus = '2'
    @destroyable = false
    @master = (role == :master)? true : false
    @backup = (role == :backup)? true : false
  end

  def backup_storage(size)
    backup_storage = {
      '/mnt/storage' => {
        :type       => 'data',
        :size       => size,
        :persistent => true,
      },
    }
    modify_storage(backup_storage)
  end

  def master?
    @master
  end

  def backup?
    @backup
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

    if @virtual_service.dependant_instances and ! @virtual_service.dependant_instances.nil? and @virtual_service.dependant_instances != []
      enc['role::databaseserver'].merge!({
        'dependencies' => @virtual_service.dependency_config,
        'dependant_instances' => @virtual_service.dependant_instances,
      })
      enc.merge!(@virtual_service.dependant_instance_mysql_rights)
    end
    enc
  end

end

