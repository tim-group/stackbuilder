require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::MysqlServer < Stacks::MachineDef
  attr_accessor :config
  attr_accessor :master
  attr_accessor :version
  attr_accessor :server_id
  attr_accessor :use_gtids
  attr_accessor :monitoring_checks
  attr_accessor :grant_user_rights_by_default

  def initialize(base_hostname, i, mysql_cluster, role, location)
    index = sprintf("%03d", i)
    @master = (role == :master) ? true : false
    @backup = (role == :backup) ? true : false
    super(base_hostname, [:mgmt, :prod], location)

    @config = {}
    @destroyable = false
    @i = i
    @index = index
    @location = location
    @ram = '4194304' # 4GB
    @role = role
    @server_id = nil
    @use_gtids = false
    @vcpus = '2'
    @version = '5.1.49-1ubuntu8'
    @mysql_cluster = mysql_cluster
    master_monitoring_checks = %w(heartbeat)
    slave_monitoring_checks = %w(replication_running replication_delay)
    @monitoring_checks = (role == :master) ? master_monitoring_checks : slave_monitoring_checks
    @grant_user_rights_by_default = false

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
    if @server_id.nil?
      case @role
      when :master
        @server_id = @i + @mysql_cluster.server_id_offset
      when :slave
        @server_id = @i + @mysql_cluster.server_id_offset
        @server_id = @i + @mysql_cluster.server_id_offset + 100 if @location == :secondary_site
      when :backup
        @server_id = @i + @mysql_cluster.server_id_offset + 200
      when :user
        @server_id = @i + @mysql_cluster.server_id_offset + 300
      end
    end
    @server_id
  end

  def data_size(size)
    modify_storage('/mnt/data' => { :size => size })
  end

  def create_persistent_storage_override
    modify_storage('/mnt/data' => {
                     :persistence_options => { :on_storage_not_found => 'create_new' }
                   })
    modify_storage('/mnt/storage' => {
                     :persistence_options => { :on_storage_not_found => 'create_new' }
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
        'log_slave_updates'        => 'ON',
        'log_bin'                  => 'mysqld-bin'
      }
    }
    recurse_merge(@config, gtid_config)
  end

  def to_enc
    enc = super()
    enc.merge!('role::mysql_server' => {
                 'backup'                   => backup?,
                 'database_name'            => @mysql_cluster.database_name,
                 'datadir'                  => '/mnt/data/mysql',
                 'environment'              => environment.name,
                 'master'                   => master?,
                 'server_id'                => server_id,
                 'charset'                  => @mysql_cluster.charset,
                 'version'                  => @version,
                 'monitoring_checks'        => @monitoring_checks
               },
               'server::default_new_mgmt_net_local' => nil)
    enc.merge!(@environment.cross_site_routing(@fabric)) if @environment.cross_site_routing_required?

    dependant_instances = @mysql_cluster.dependant_instance_fqdns(location, [:prod], false)
    dependant_instances.concat(@mysql_cluster.fqdn_list(@mysql_cluster.children))
    dependant_instances.delete prod_fqdn

    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::mysql_server'].merge!('dependencies' => @mysql_cluster.dependency_config(fabric),
                                       'dependant_instances' => dependant_instances)
      unless backup?
        enc.merge!(@mysql_cluster.dependant_instance_mysql_rights(location))
      end
    end
    @config = merge_gtid_config if @use_gtids

    unless @mysql_cluster.allowed_hosts.empty?
      enc['role::mysql_allow_hosts'] = {
        'hosts' => @mysql_cluster.allowed_hosts
      }
    end

    unless @config.empty?
      enc['role::stacks_mysql_config'] = {
        'config'        => @config,
        'restart_mysql' => !@environment.production
      }
    end
    if @mysql_cluster.enable_percona_checksum_tools
      enc['percona::checksum_tools'] = {
        'database_name' => @mysql_cluster.database_name,
        'master_fqdns'  => @mysql_cluster.master_servers,
        'is_master'     => master?,
        'ignore_tables' => @mysql_cluster.percona_checksum_ignore_tables
      }
    end

    if @role == :user_access || @mysql_cluster.grant_user_rights_by_default || @grant_user_rights_by_default
      enc['role::mysql_multiple_rights'] = {
        'rights' => {
          @mysql_cluster.database_name => {
            'environment'   => environment.name,
            'database_name' => @mysql_cluster.database_name
          }
        }
      }
    end

    replication_rights_class = 'mysql_hacks::replication_rights_wrapper'
    enc[replication_rights_class] = {} if enc[replication_rights_class].nil?
    enc[replication_rights_class]['rights'] = {} if enc[replication_rights_class]['rights'].nil?
    enc[replication_rights_class]['rights'].merge!(@mysql_cluster.dependant_children_replication_mysql_rights(self))
    enc
  end
end
