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
    @ram = '4194304' # 4GB
    @vcpus = '2'
    @destroyable = false
    @master = (role == :master)? true : false
    @backup = (role == :backup)? true : false

    storage = {
      '/mnt/data' => {
        :type       => 'data',
        :size       => '10G',
        :persistent => true,
      }
    }
    backup_storage = {
      '/mnt/storage' => {
        :type       => 'data',
        :size       => '10G',
        :persistent => true,
      },
    }
    modify_storage(storage)
    modify_storage(backup_storage) if @backup
  end

  def backup_size(size)
    modify_storage({'/mnt/storage' => { :size => size }}) if @backup
  end

  def data_size(size)
    modify_storage({'/mnt/data' => { :size => size }})
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

    dependant_instances = @virtual_service.dependant_instances_including_children
    dependant_instances.delete self.prod_fqdn


    if dependant_instances and !dependant_instances.nil? and dependant_instances != []
      enc['role::databaseserver'].merge!({
        'dependencies' => @virtual_service.dependency_config,
        'dependant_instances' => dependant_instances,
      })
      enc.merge!(@virtual_service.dependant_instance_mysql_rights)
    end
    enc
  end

end

