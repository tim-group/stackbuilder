require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::MysqlServer < Stacks::MachineDef
  attr_accessor :config
  attr_accessor :master
  attr_accessor :version
  attr_accessor :server_id
  attr_accessor :use_gtids

  def initialize(base_hostname, virtual_service, role, location)
    @master = (role == :master) ? true : false
    @backup = (role == :backup) ? true : false
    super(base_hostname, [:mgmt, :prod], location)

    @config = {}
    @destroyable = false
    @location = location
    @ram = '4194304' # 4GB
    @server_id = nil
    @use_gtids = false
    @vcpus = '2'
    @version = '5.1.49-1ubuntu8'
    @virtual_service = virtual_service

    storage = {
      '/tmp' => {
        :type       => 'os',
        :size       => '10G',
        :persistent => false
      },
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

  def server_id
    return virtual_service.server_id(self) if @server_id.nil?
    @server_id
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

  def master?
    @master
  end

  def backup?
    @backup
  end

  def merge_gtid_config
    gtid_config = {
      'mysqld' => {
        'gtid_mode'                => 'ON',
        'enforce_gtid_consistency' => 'ON',
        'log_slave_updates'        => 'ON'
      }
    }
    recurse_merge(@config, gtid_config)
  end

  def to_enc
    enc = super()
    enc.merge!('role::mysql_server' => {
                 'backup'                   => backup?,
                 'database_name'            => @virtual_service.database_name,
                 'datadir'                  => '/mnt/data/mysql',
                 'environment'              => environment.name,
                 'master'                   => master?,
                 'server_id'                => server_id,
                 'charset'                  => @virtual_service.charset,
                 'version'                  => @version
               },
               'server::default_new_mgmt_net_local' => nil)
    enc.merge!(@environment.cross_site_routing(@fabric)) if @environment.cross_site_routing_required?

    dependant_instances = @virtual_service.dependant_instance_fqdns(location)
    dependant_instances.concat(@virtual_service.fqdn_list(@virtual_service.children))
    dependant_instances.delete prod_fqdn

    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::mysql_server'].merge!('dependencies' => @virtual_service.dependency_config(location),
                                       'dependant_instances' => dependant_instances)
      unless backup?
        enc.merge!(@virtual_service.dependant_instance_mysql_rights(location))
      end
    end
    @config = merge_gtid_config if @use_gtids

    unless @config.empty?
      enc['role::stacks_mysql_config'] = {
        'config'        => @config,
        'restart_mysql' => !@environment.production
      }
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
