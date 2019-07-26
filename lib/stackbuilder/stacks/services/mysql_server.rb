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
  attr_accessor :snapshot_size, :snapshot_pv_size
  attr_accessor :snapshot_frequency_secs, :snapshot_retention_secs

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)

    @config = {}
    @destroyable = false
    @ram = '4194304' # 4GB
    @server_id = nil
    @use_gtids = false
    @vcpus = '2'
    @version = '5.6.25-1'
    @monitoring_checks = monitoring_checks
    @grant_user_rights_by_default = false

    @snapshot_pv_size = '20G'
    @snapshot_size = '512M'
    @snapshot_frequency_secs = 86400
    @snapshot_retention_secs = 86400 * 7

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
      checks << 'checksum' if @virtual_service.percona_checksum && @virtual_service.percona_checksum_monitoring

      if @virtual_service.master_instances > 1
        checks += %w(replication_running replication_delay)
      end
    else
      checks = %w(replication_running replication_delay)
      checks << 'checksum' if @virtual_service.percona_checksum && @virtual_service.percona_checksum_monitoring
    end

    checks
  end

  def snapshot_pv_size(size)
    snapshot_storage = {
      '/mnt/data' => {
        :prepare => {
          :options => {
            :create_guest_lvm  => true,
            :guest_lvm_pv_size => size
          }
        }
      }
    }
    modify_storage(snapshot_storage) if role_of?(:backup) && @virtual_service.snapshot_backups
  end

  def server_id_legacy
    if @server_id.nil?
      case @role
      when :master, :standalone
        @server_id = index + @virtual_service.server_id_offset
      when :slave
        @server_id = index + @virtual_service.server_id_offset
        @server_id = index + @virtual_service.server_id_offset + 100 if @location == :secondary_site
      when :backup
        @server_id = index + @virtual_service.server_id_offset + 200
      when :user_access
        @server_id = index + @virtual_service.server_id_offset + 300
      else
        fail "Unable to establish server_id - Unknown type of mysql server #{@role}"
      end
    end
    @server_id
  end

  def server_id
    return server_id_legacy unless @virtual_service.role_in_name
    if @server_id.nil?
      id = @virtual_service.server_id_offset + index
      case @role
      when :master, :standalone
        id += 50 if @location == :secondary_site
      when :slave
        id += 100
        id += 50 if @location == :secondary_site
      when :backup
        id += 200
        id += 50 if @location == :secondary_site
      when :user_access
        id += 300
        id += 50 if @location == :secondary_site
      else
        fail "Unable to establish server_id - Unknown type of mysql server #{@role}"
      end
      @server_id = id
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

  def dependencies_inside_service
    @virtual_service.children.select { |m| m.identity != identity }
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
        'replicate-do-db' => [@virtual_service.database_name, 'percona']
      }
    }
    recurse_merge!(@config, default_config)
  end

  def percona_checksum_enc
    return {} if !@virtual_service.percona_checksum || @virtual_service.master_instances == 0
    ignore_tables = ["#{@virtual_service.database_name}.heartbeat"]
    ignore_tables.push(@virtual_service.percona_checksum_ignore_tables.flatten)
    {
      'percona::checksum_tools' => {
        'database_name' => @virtual_service.database_name,
        'master_fqdns'  => @virtual_service.master_servers.map(&:prod_fqdn).sort,
        'is_master'     => role_of?(:master),
        'ignore_tables' => ignore_tables.join(',')
      }
    }
  end

  def snapshot_enc
    {
      'db_snapshot' => {
        'lv_to_snapshot'          => '_mnt_data',
        'snapshot_size'           => @snapshot_size,
        'snapshot_frequency_secs' => @snapshot_frequency_secs,
        'snapshot_retention_secs' => @snapshot_retention_secs
      }
    }
  end

  def user_rights_enc
    create_read_only_users = false
    create_read_only_users = true if @role == :user_access ||
                                     @virtual_service.grant_user_rights_by_default ||
                                     @grant_user_rights_by_default

    {
      'role::mysql_multiple_rights' => {
        'rights' => {
          @virtual_service.database_name => {
            'create_read_only_users' => create_read_only_users,
            'environment'            => environment.name,
            'database_name'          => @virtual_service.database_name
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

  def allowed_hosts_enc
    return {} if @virtual_service.allowed_hosts.empty?
    {
      'role::mysql_allow_hosts' => {
        'hosts' => @virtual_service.allowed_hosts
      }
    }
  end

  def to_enc
    dist_version = version
    unless version == '5.1.49-1ubuntu8'
      dist_version = case @lsbdistcodename
                     when 'precise'
                       "#{version}ubuntu12.04"
                     when 'trusty'
                       "#{version}ubuntu14.04"
                     when 'xenial'
                       "#{version}ubuntu16.04"
                     else
                       fail "Unable to establish version for mysql version #{version} on #{@lsbdistcodename}"
      end
    end
    enc = super()
    enc.merge!('role::mysql_server' => {
                 'database_name'            => @virtual_service.database_name,
                 'datadir'                  => '/mnt/data/mysql',
                 'environment'              => environment.name,
                 'role'                     => @role,
                 'server_id'                => server_id,
                 'charset'                  => @virtual_service.charset,
                 'version'                  => dist_version,
                 'monitoring_checks'        => @monitoring_checks
               })

    dependant_instances = @virtual_service.dependant_instance_fqdns(location, [:prod], false)
    dependant_instances.concat(@virtual_service.children.map(&:prod_fqdn))
    dependant_instances.delete prod_fqdn

    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      unless role_of?(:backup) || role_of?(:user_access)
        recurse_merge!(enc, @virtual_service.dependant_instance_mysql_rights)
      end
    end

    recurse_merge!(enc, @environment.cross_site_routing(@fabric)) if @environment.cross_site_routing_required?
    recurse_merge!(enc, allowed_hosts_enc)
    recurse_merge!(enc, config_enc)
    recurse_merge!(enc, percona_checksum_enc)
    recurse_merge!(enc, user_rights_enc)
    recurse_merge!(enc, snapshot_enc) if role_of?(:backup) && @virtual_service.snapshot_backups

    replication_rights_class = 'mysql_hacks::replication_rights_wrapper'
    enc[replication_rights_class] = {} if enc[replication_rights_class].nil?
    enc[replication_rights_class]['rights'] = {} if enc[replication_rights_class]['rights'].nil?
    enc[replication_rights_class]['rights'].merge!(@virtual_service.dependant_children_replication_mysql_rights(self))

    enc
  end
end
