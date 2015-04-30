require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Services::MysqlServer < Stacks::MachineDef
  attr_accessor :master

  def initialize(base_hostname, virtual_service, role, location)
    @master = (role == :master) ? true : false
    @backup = (role == :backup) ? true : false
    @location = location

    super(base_hostname, [:mgmt, :prod], location)
    @virtual_service = virtual_service
    @ram = '4194304' # 4GB
    @vcpus = '2'
    @destroyable = false

    storage = {
      '/mnt/data' => {
        :type       => 'data',
        :size       => '10G',
        :persistent => true
      }
    }
    backup_storage = {
      '/mnt/storage' => {
        :type       => 'data',
        :size       => '10G',
        :persistent => true
      }
    }
    modify_storage(storage)
    modify_storage(backup_storage) if @backup
  end

  def backup_size(size)
    modify_storage('/mnt/storage' => { :size => size }) if @backup
  end

  def data_size(size)
    modify_storage('/mnt/data' => { :size => size })
  end

  def create_persistent_storage_override
    modify_storage('/mnt/data' => {
                     :persistence_options => { :on_storage_not_found => :create_new }
                   })
    modify_storage('/mnt/storage' => {
                     :persistence_options => { :on_storage_not_found => :create_new }
                   }) if backup?
  end

  # rubocop:disable Style/TrivialAccessors
  def master?
    @master
  end
  # rubocop:enable Style/TrivialAccessors

  # rubocop:disable Style/TrivialAccessors
  def backup?
    @backup
  end
  # rubocop:enable Style/TrivialAccessors

  def config
    {}
  end

  def server_id
    @virtual_service.children.index(self) + 1
  end

  def to_enc
    enc = {
      'role::mysql_server' => {
        'backup'                   => backup?,
        'config'                   => config,
        'database_name'            => @virtual_service.database_name,
        'datadir'                  => '/mnt/data/mysql',
        'environment'              => environment.name,
        'master'                   => master?,
        'server_id'                => server_id,
        'charset'                  => @virtual_service.charset
      },
      'server::default_new_mgmt_net_local' => nil
    }
    enc.merge!(@environment.cross_site_routing(@fabric)) if @environment.cross_site_routing_required?

    dependant_instances = @virtual_service.dependant_machine_def_with_children_fqdns
    dependant_instances.delete prod_fqdn

    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::mysql_server'].merge!('dependencies' => @virtual_service.dependency_config(location),
                                       'dependant_instances' => dependant_instances)
      unless backup?
        enc.merge!(@virtual_service.dependant_instance_mysql_rights)
      end
    end
    enc['role::mysql_multiple_rights'] = {
      'rights' => {
        @virtual_service.database_name => {
          'environment'   => environment.name,
          'database_name' => @virtual_service.database_name
        }
      }
    }
    enc.merge!(@virtual_service.dependant_children_replication_mysql_rights(self))
    enc
  end
end
