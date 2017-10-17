require 'stackbuilder/stacks/namespace'

module Stacks::Services::MysqlCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :backup_instance_site
  attr_accessor :charset
  attr_accessor :database_name
  attr_accessor :include_master_in_read_only_cluster
  attr_accessor :read_only_cluster_master_last
  attr_accessor :percona_checksum
  attr_accessor :percona_checksum_ignore_tables
  attr_accessor :percona_checksum_monitoring
  attr_accessor :server_id_base
  attr_accessor :server_id_offset
  attr_accessor :supported_requirements
  attr_reader :grant_user_rights_by_default

  attr_accessor :master_instances
  attr_accessor :slave_instances
  attr_accessor :secondary_site_slave_instances
  attr_accessor :backup_instances
  attr_accessor :primary_site_backup_instances
  attr_accessor :user_access_instances
  attr_accessor :secondary_site_user_access_instances
  attr_accessor :standalone_instances
  attr_accessor :snapshot_backups

  def configure
    @backup_instance_site = :secondary_site
    @charset = 'utf8'
    @database_name = ''
    @percona_checksum = true
    @grant_user_rights_by_default = true
    @include_master_in_read_only_cluster = true
    @read_only_cluster_master_last = false
    @master_index_offset = 0
    @percona_checksum_ignore_tables = []
    @percona_checksum_monitoring = false
    @server_id_offset = 0
    @supported_requirements = {}

    @master_instances = 1
    @slave_instances = 1
    @secondary_site_slave_instances = 0
    @backup_instances = 1
    @primary_site_backup_instances = 0
    @user_access_instances = 0
    @secondary_site_user_access_instances = 0
    @standalone_instances = 0
    @role_in_name = true

    @snapshot_backups = false
  end

  def instantiate_machines(environment)
    fail 'MySQL clusters do not currently support enable_secondary_site' if @enable_secondary_site
    validate_supported_requirements_specify_at_least_one_server
    on_bind { validate_supported_requirements_servers_exist_on_bind }

    server_index = @master_index_offset
    @master_instances.times do
      instantiate_machine(server_index += 1, environment, environment.sites.first, :master)
    end

    server_index = 0 if @role_in_name
    @slave_instances.times do
      instantiate_machine(server_index += 1, environment, environment.sites.first, :slave)
    end
    server_index = 0
    @backup_instances.times do
      instantiate_machine(server_index += 1, environment, environment.options[backup_instance_site], :backup, 'backup')
    end
    server_index = 0
    @primary_site_backup_instances.times do
      instantiate_machine(server_index += 1, environment, environment.sites.first, :backup, 'backup')
    end
    server_index = 0
    @secondary_site_slave_instances.times do
      instantiate_machine(server_index += 1, environment, environment.sites.last, :slave)
    end
    server_index = 0
    @user_access_instances.times do
      @grant_user_rights_by_default = false
      instantiate_machine(server_index += 1, environment, environment.sites.first, :user_access, 'useraccess')
    end
    server_index = 0
    @secondary_site_user_access_instances.times do
      @grant_user_rights_by_default = false
      instantiate_machine(server_index += 1, environment, environment.sites.last, :user_access, 'useraccess')
    end
    server_index = 0
    @standalone_instances.times do
      instantiate_machine(server_index += 1, environment, environment.sites.first, :standalone)
    end
  end

  def single_instance
    @master_instances = 1
    @slave_instances = 0
    @backup_instances = 0
  end

  def clazz
    'mysqlcluster'
  end

  def create_persistent_storage_override
    each_machine(&:create_persistent_storage_override)
  end

  def dependant_children_replication_mysql_rights(server)
    rights = {}
    children.each do |dependant|
      next if dependant == server

      rights.merge!(
        "replicant@#{dependant.prod_fqdn}" => {
          'password_hiera_key' => "#{dependant.environment.name}/#{database_name}/replication/mysql_password"
        })
    end
    rights
  end

  def dependant_instance_mysql_rights
    rights = {
      'mysql_hacks::application_rights_wrapper' => { 'rights' => {} }
    }
    virtual_services_that_depend_on_me.each do |service|
      service.children.each do |dependant|
        rights['mysql_hacks::application_rights_wrapper']['rights'].
          merge!(
            "#{mysql_username(service)}@#{dependant.prod_fqdn}/#{database_name}" =>
            { 'password_hiera_key' => "#{service.environment.name}/#{service.database_username}/mysql_password" })
      end
    end
    rights
  end

  def validate_dependant_requirement(dependent, requirement)
    fail "Stack '#{name}' does not support requirement '#{requirement}' in environment '#{environment.name}'. " \
         "supported_requirements is empty or unset." if @supported_requirements.empty? && !requirement.nil?
    fail "'#{dependent.name}' must declare its requirement on '#{name}' as it declares supported requirements "\
         "in environment '#{environment.name}'. Supported requirements: "\
         "[#{@supported_requirements.keys.sort.join(',')}]." if !@supported_requirements.empty? && requirement.nil?
  end

  def config_params(dependent, fabric)
    requirement = requirement_of(dependent)
    validate_dependant_requirement(dependent, requirement)

    ### FIXME: rpearce 26/04/2016
    ### This can be removed when all apps specify a requirement
    if @supported_requirements.empty? && requirement.nil?
      config_given_no_requirement(dependent, fabric)
    ### This can be moved to validate_dependant_requirement when all apps specify a requirement
    elsif !@supported_requirements.include?(requirement)
      fail "Stack '#{name}' does not support requirement '#{requirement}' in environment '#{environment.name}'. " \
        "Supported requirements: [#{@supported_requirements.keys.sort.join(',')}]."
    else
      # Convert the fqdn array to an array of server objects ensuring the same order
      servers = @supported_requirements[requirement].inject([]) do |s, fqdn|
        s << children.find { |server| server.prod_fqdn == fqdn }
      end
      config_to_fulfil_requirement(dependent, servers, requirement)
    end
  end

  def master_servers
    masters = children.reject { |mysql_server| !mysql_server.master? }
    fail "No masters were not found! #{children}" if masters.empty?
    masters.collect(&:prod_fqdn).sort
  end

  private

  def validate_supported_requirements_specify_at_least_one_server
    @supported_requirements.each_pair do |requirement, hosts|
      if hosts.nil? || hosts.empty?
        fail "Attempting to support requirement '#{requirement}' with no servers assigned to it."
      end
    end
  end

  def validate_supported_requirements_servers_exist_on_bind
    @supported_requirements.each_pair do |requirement, hosts|
      hosts.each do |host|
        if children.find { |server| server.prod_fqdn == host }.nil?
          fail "Attempting to support requirement '#{requirement}' with non-existent server '#{host}'. " \
            "Available servers: [#{children.map(&:prod_fqdn).sort.join(',')}]."
        end
      end
    end
  end

  def read_only_cluster_servers(fabric)
    servers = children.select do |server|
      if server.master? && !@include_master_in_read_only_cluster
        false
      elsif server.role_of?(:user_access)
        false
      elsif server.backup?
        false
      else
        true
      end
    end
    if @read_only_cluster_master_last
      servers.sort_by! { |server| server.master? ? 1 : 0 }
    else
      servers.sort_by!(&:prod_fqdn)
    end
    servers.select { |server| server.fabric == fabric }.inject([]) do |prod_fqdns, server|
      prod_fqdns << server.prod_fqdn
      prod_fqdns
    end
  end

  def secondary_servers(location)
    children.select do |server|
      !server.master? && !server.backup? && server.location == location
    end.inject([]) do |slaves, server|
      slaves << server.prod_fqdn
      slaves
    end
  end

  def mysql_username(service)
    # MySQL user names can be up to 16 characters long: https://dev.mysql.com/doc/refman/5.5/en/user-names.html
    service.database_username[0..15]
  end

  def config_given_no_requirement(dependent, fabric)
    config_properties(dependent, [master_servers.first], read_only_cluster_servers(fabric))
  end

  def requirement_of(dependant)
    dependent_on_this_cluster = dependant.depends_on.find { |dependency| dependency[0] == name }
    dependent_on_this_cluster[2]
  end

  def config_to_fulfil_requirement(dependent, hosts, requirement)
    master = []
    read_only_slaves = []
    if (requirement == :master_with_slaves)
      master = [hosts.select(&:master?).map(&:prod_fqdn).first]
      read_only_slaves = hosts.reject(&:master?).map(&:prod_fqdn)
    else
      master = read_only_slaves = hosts.map(&:prod_fqdn)
    end
    config_properties(dependent, master, read_only_slaves)
  end

  def config_properties(dependent, master, read_only_cluster)
    config_params = {
      "db.#{@database_name}.hostname"           => master.join(','),
      "db.#{@database_name}.database"           => database_name,
      "db.#{@database_name}.driver"             => 'com.mysql.jdbc.Driver',
      "db.#{@database_name}.port"               => '3306',
      "db.#{@database_name}.username"           => mysql_username(dependent),
      "db.#{@database_name}.password_hiera_key" =>
        "#{dependent.environment.name}/#{dependent.application}/mysql_password"
    }
    config_params["db.#{@database_name}.read_only_cluster"] =
        read_only_cluster.join(",") unless read_only_cluster.empty?

    config_params
  end
end
