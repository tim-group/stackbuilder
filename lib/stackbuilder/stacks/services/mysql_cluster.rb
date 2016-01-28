require 'stackbuilder/stacks/namespace'

module Stacks::Services::MysqlCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :backup_instances
  attr_accessor :primary_site_backup_instances
  attr_accessor :charset
  attr_accessor :database_name
  attr_accessor :master_instances
  attr_accessor :secondary_site_slave_instances
  attr_accessor :server_id_base
  attr_accessor :server_id_offset
  attr_accessor :slave_instances
  attr_accessor :include_master_in_read_only_cluster
  attr_accessor :backup_instance_site
  attr_accessor :supported_requirements
  attr_accessor :enable_percona_checksum_tools
  attr_accessor :percona_checksum_ignore_tables
  attr_accessor :user_access_instances
  attr_accessor :secondary_site_user_access_instances
  attr_reader :grant_user_rights_by_default

  def configure
    @database_name = ''
    @master_instances = 1
    @slave_instances = 1
    @secondary_site_slave_instances = 0
    @backup_instances = 1
    @primary_site_backup_instances = 0
    @charset = 'utf8'
    @server_id_offset = 0
    @include_master_in_read_only_cluster = true
    @master_index_offset = 0
    @backup_instance_site = :secondary_site
    @supported_requirements = {}
    @enable_percona_checksum_tools = false
    @percona_checksum_ignore_tables = ''
    @user_access_instances = 0
    @secondary_site_user_access_instances = 0
    @grant_user_rights_by_default = true
  end

  def instantiate_machine(name, type, i, environment, location)
    index = sprintf("%03d", i)
    server_name = "#{name}-#{index}"
    server_name = "#{name}#{type}-#{index}" if type == :backup
    server_name = "#{name}useraccess-#{index}" if type == :user_access
    server = @type.new(server_name, i, self, type, location)
    server.group = groups[i % groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    @definitions["#{server_name}-#{location}"] = server
  end

  def instantiate_machines(environment)
    fail 'MySQL clusters do not currently support enable_secondary_site' if @enable_secondary_site
    validate_supported_requirements_specify_at_least_one_server
    on_bind { validate_supported_requirements_servers_exist_on_bind }

    i = @master_index_offset
    @master_instances.times do
      instantiate_machine(name, :master, i += 1, environment, :primary_site)
    end
    @slave_instances.times do
      instantiate_machine(name, :slave, i += 1, environment, :primary_site)
    end
    i = 0
    @backup_instances.times do
      instantiate_machine(name, :backup, i += 1, environment, @backup_instance_site)
    end
    i = 0
    @primary_site_backup_instances.times do
      instantiate_machine(name, :backup, i += 1, environment, :primary_site)
    end
    i = 0
    @secondary_site_slave_instances.times do
      instantiate_machine(name, :slave, i += 1, environment, :secondary_site)
    end
    i = 0
    @user_access_instances.times do
      @grant_user_rights_by_default = false
      instantiate_machine(name, :user_access, i += 1, environment, :primary_site)
    end
    i = 0
    @secondary_site_user_access_instances.times do
      @grant_user_rights_by_default = false
      instantiate_machine(name, :user_access, i += 1, environment, :secondary_site)
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

  def data_size(size)
    each_machine do |machine|
      machine.data_size(size)
    end
  end

  def backup_size(size)
    each_machine do |machine|
      machine.backup_size(size) if machine.backup?
    end
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
          'password_hiera_key' => "enc/#{dependant.environment.name}/#{database_name}/replication/mysql_password"
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
            { 'password_hiera_key' => "enc/#{service.environment.name}/#{service.database_username}/mysql_password" })
      end
    end
    rights
  end

  def config_params(dependent, fabric)
    requirement = requirement_of(dependent)
    if @supported_requirements.empty? && !requirement.nil?
      fail "Stack '#{name}' does not support requirement '#{requirement}' in environment '#{environment.name}'. " \
        "supported_requirements is empty or unset."
    elsif !@supported_requirements.empty? && requirement.nil?
      fail "'#{dependent.name}' must declare it's requirement on '#{name}' as it declares supported requirements "\
        "in environment '#{environment.name}'. "\
        "Supported requirements: [#{@supported_requirements.keys.sort.join(',')}]."
    elsif @supported_requirements.empty? && requirement.nil?
      config_given_no_requirement(dependent, fabric)
    elsif !@supported_requirements.include?(requirement)
      fail "Stack '#{name}' does not support requirement '#{requirement}' in environment '#{environment.name}'. " \
        "Supported requirements: [#{@supported_requirements.keys.sort.join(',')}]."
    else

      hostnames_for_requirement = @supported_requirements[requirement]
      matching_hostnames = children.select { |server| hostnames_for_requirement.include?(server.prod_fqdn) }

      config_to_fulfil_requirement(dependent, matching_hostnames)
    end
  end

  def master_servers
    masters = children.reject { |mysql_server| !mysql_server.master? }
    fail "No masters were not found! #{children}" if masters.empty?
    masters.collect(&:prod_fqdn)
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
            "Available servers: [#{children.map(&:prod_fqdn).join(',')}]."
        end
      end
    end
  end

  def all_servers(fabric)
    children.select do |server|
      if server.master? && !@include_master_in_read_only_cluster
        false
      elsif server.role_of?(:user_access)
        false
      elsif server.backup?
        false
      else
        true
      end
    end.select { |server| server.fabric == fabric }.inject([]) do |prod_fqdns, server|
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
    config_properties(dependent, [master_servers.first], all_servers(fabric))
  end

  def requirement_of(dependant)
    dependent_on_this_cluster = dependant.depends_on.find { |dependency| dependency[0] == name }
    dependent_on_this_cluster[2]
  end

  def config_to_fulfil_requirement(dependent, hosts)
    hosts_fqdns = hosts.map(&:prod_fqdn)
    config_properties(dependent, hosts_fqdns, hosts_fqdns)
  end

  def config_properties(dependent, hostnames, read_only_cluster)
    config_params = {
      "db.#{@database_name}.hostname"           => hostnames.join(','),
      "db.#{@database_name}.database"           => database_name,
      "db.#{@database_name}.driver"             => 'com.mysql.jdbc.Driver',
      "db.#{@database_name}.port"               => '3306',
      "db.#{@database_name}.username"           => mysql_username(dependent),
      "db.#{@database_name}.password_hiera_key" =>
        "enc/#{dependent.environment.name}/#{dependent.application}/mysql_password"
    }
    config_params["db.#{@database_name}.read_only_cluster"] =
        read_only_cluster.join(",") unless read_only_cluster.empty?

    config_params
  end
end
