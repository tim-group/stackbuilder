require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::MysqlServer < Stacks::MachineDef
  attr_accessor :config
  attr_accessor :role
  attr_accessor :version
  attr_accessor :server_id
  attr_accessor :use_gtids
  attr_accessor :monitoring_checks
  attr_accessor :grant_user_rights_by_default

  def initialize(base_hostname, i, mysql_cluster, role, location)
    index = sprintf("%03d", i)
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
    @version = '5.6.25-1ubuntu12.04'
    @mysql_cluster = mysql_cluster
    @monitoring_checks = monitoring_checks
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
    modify_storage(backup_storage) if role_of?(:backup)
  end

  def monitoring_checks
    checks = []
    case @role
    when :standalone
      return []
    when :master
      checks = %w(heartbeat)
      checks << 'checksum' if @mysql_cluster.enable_percona_checksum_tools
    else
      checks = %w(replication_running replication_delay)
      checks << 'checksum' if @mysql_cluster.enable_percona_checksum_tools
    end
    checks
  end

  def backup_size(size)
    modify_storage('/mnt/storage' => { :size => size }) if role_of?(:backup)
  end

  def server_id
    if @server_id.nil?
      case @role
      when :master, :standalone
        @server_id = @i + @mysql_cluster.server_id_offset
      when :slave
        @server_id = @i + @mysql_cluster.server_id_offset
        @server_id = @i + @mysql_cluster.server_id_offset + 100 if @location == :secondary_site
      when :backup
        @server_id = @i + @mysql_cluster.server_id_offset + 200
      when :user_access
        @server_id = @i + @mysql_cluster.server_id_offset + 300
      else
        fail "Unable to establish server_id - Unknown type of mysql server #{@role}"
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
                   }) if role_of?(:backup)
  end

  def role_of?(role)
    @role == role
  end

  def master?
    role_of?(:master)
  end

  def backup?
    role_of?(:backup)
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
    recurse_merge!(@config, gtid_config)
  end

  def merge_default_config
    default_config = {
      'mysqld' => {
        'replicate-do-db'=> [ @mysql_cluster.database_name, 'percona'],
      }
    }
    recurse_merge!(@config, default_config)
  end

  def percona_checksum_tools_enc
    ignore_tables = ["#{@mysql_cluster.database_name}.heartbeat"]
    ignore_tables.push(@mysql_cluster.percona_checksum_ignore_tables.flatten)
    return {} unless @mysql_cluster.enable_percona_checksum_tools
    {
      'percona::checksum_tools' => {
        'database_name' => @mysql_cluster.database_name,
        'master_fqdns'  => @mysql_cluster.master_servers,
        'is_master'     => role_of?(:master),
        'ignore_tables' => ignore_tables.join(',')
      }
    }
  end

  def user_rights_enc
    create_read_only_users = false
    create_read_only_users = true if @role == :user_access ||
                                     @mysql_cluster.grant_user_rights_by_default ||
                                     @grant_user_rights_by_default

    {
      'role::mysql_multiple_rights' => {
        'rights' => {
          @mysql_cluster.database_name => {
            'create_read_only_users' => create_read_only_users,
            'environment'            => environment.name,
            'database_name'          => @mysql_cluster.database_name
          }
        }
      }
    }
  end

  def config_enc
    merge_gtid_config if @use_gtids
    merge_default_config
    return {} if @config.empty?
    {
      'role::stacks_mysql_config' => {
        'config'        => @config,
        'restart_mysql' => !@environment.production
      }
    }
  end

  def dependant_instances_enc(dependant_instances)
    {
      'role::mysql_server' =>  {
        'dependencies' => @mysql_cluster.dependency_config(fabric),
        'dependant_instances' => dependant_instances
      }
    }
  end

  def allowed_hosts_enc
    return {} if @mysql_cluster.allowed_hosts.empty?
    {
      'role::mysql_allow_hosts' => {
        'hosts' => @mysql_cluster.allowed_hosts
      }
    }
  end

  def to_enc
    enc = super()
    enc.merge!('role::mysql_server' => {
                 'database_name'            => @mysql_cluster.database_name,
                 'datadir'                  => '/mnt/data/mysql',
                 'environment'              => environment.name,
                 'role'                     => @role,
                 'server_id'                => server_id,
                 'charset'                  => @mysql_cluster.charset,
                 'version'                  => @version,
                 'monitoring_checks'        => @monitoring_checks
               },
               'server::default_new_mgmt_net_local' => nil)

    dependant_instances = @mysql_cluster.dependant_instance_fqdns(location, [:prod], false)
    dependant_instances.concat(@mysql_cluster.children.map(&:prod_fqdn)).sort
    dependant_instances.delete prod_fqdn

    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      recurse_merge!(enc, dependant_instances_enc(dependant_instances))
      unless role_of?(:backup) || role_of?(:user_access)
        recurse_merge!(enc, @mysql_cluster.dependant_instance_mysql_rights)
      end
    end

    recurse_merge!(enc, @environment.cross_site_routing(@fabric)) if @environment.cross_site_routing_required?
    recurse_merge!(enc, allowed_hosts_enc)
    recurse_merge!(enc, config_enc)
    recurse_merge!(enc, percona_checksum_tools_enc)
    recurse_merge!(enc, user_rights_enc)

    replication_rights_class = 'mysql_hacks::replication_rights_wrapper'
    enc[replication_rights_class] = {} if enc[replication_rights_class].nil?
    enc[replication_rights_class]['rights'] = {} if enc[replication_rights_class]['rights'].nil?
    enc[replication_rights_class]['rights'].merge!(@mysql_cluster.dependant_children_replication_mysql_rights(self))

    enc
  end
end
