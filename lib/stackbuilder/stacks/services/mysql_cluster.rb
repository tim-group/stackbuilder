require 'stackbuilder/stacks/namespace'

module Stacks::Services::MysqlCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :backup_instances
  attr_accessor :charset
  attr_accessor :database_name
  attr_accessor :master_instances
  attr_accessor :secondary_site_slave_instances
  attr_accessor :server_id_base
  attr_accessor :server_id_offset
  attr_accessor :slave_instances
  attr_accessor :include_master_in_read_only_cluster
  attr_accessor :backup_instance_site
  attr_accessor :supported_dependencies
  attr_accessor :enable_percona_checksum_tools
  attr_accessor :percona_checksum_ignore_tables

  def configure
    @database_name = ''
    @master_instances = 1
    @slave_instances = 1
    @secondary_site_slave_instances = 0
    @backup_instances = 1
    @charset = 'utf8'
    @server_id_offset = 0
    @include_master_in_read_only_cluster = true
    @master_index_offset = 0
    @backup_instance_site = :secondary_site
    @supported_dependencies = {}
    @enable_percona_checksum_tools = false
    @percona_checksum_ignore_tables = ''
  end

  def instantiate_machine(name, type, i, environment, location)
    index = sprintf("%03d", i)
    server_name = "#{name}-#{index}"
    server_name = "#{name}#{type}-#{index}" if type == :backup
    server = @type.new(server_name, i, self, type, location)
    server.group = groups[i % groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    @definitions["#{server_name}-#{location}"] = server
  end

  def instantiate_machines(environment)
    fail 'MySQL clusters do not currently support enable_secondary_site' if @enable_secondary_site
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
    @secondary_site_slave_instances.times do
      instantiate_machine(name, :slave, i += 1, environment, :secondary_site)
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

  def master_servers
    masters = children.reject { |mysql_server| !mysql_server.master? }
    fail "No masters were not found! #{children}" if masters.empty?
    [masters.first.prod_fqdn]
  end

  def all_servers(fabric)
    children.select do |server|
      if server.master? && !@include_master_in_read_only_cluster
        false
      else
        true
      end
    end.select { |server| !server.backup? && server.fabric == fabric }.inject([]) do |prod_fqdns, server|
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

  def mysql_username(service)
    # MySQL user names can be up to 16 characters long: https://dev.mysql.com/doc/refman/5.5/en/user-names.html
    service.application[0..15]
  end

  def dependant_instance_mysql_rights(location)
    rights = {
      'mysql_hacks::application_rights_wrapper' => { 'rights' => {} }
    }
    virtual_services_that_depend_on_me(location).each do |service|
      service.children.each do |dependant|
        rights['mysql_hacks::application_rights_wrapper']['rights'].
          merge!("#{mysql_username(service)}@#{dependant.prod_fqdn}/#{database_name}" =>
                 { 'password_hiera_key' => "enc/#{service.environment.name}/#{service.application}/mysql_password" })
      end
    end
    rights
  end

  def config_params(dependent, fabric)
    if @supported_dependencies.empty?
      return config_given_no_requirement(dependent, fabric)
    elsif requirement_of(dependent).nil?
      config_given_no_requirement(dependent, fabric)
    else
      servers_in_fabric = children.select do |server| server.fabric == fabric end
      hostnames_for_requirement = @supported_dependencies[requirement_of(dependent)]
      matching_hostnames = servers_in_fabric.select { |server| hostnames_for_requirement.include?(server.name) }

      config_to_fulfil_requirement(dependent, matching_hostnames)
    end
  end

  private

  def requirement_of(dependant)
    dependent_on_this_cluster = dependant.depends_on.find { |dependency| dependency[0] == self.name }
    dependent_on_this_cluster[2]
  end

  def config_given_no_requirement(dependent, fabric)
    config_params = {
        "db.#{@database_name}.hostname"           => master_servers.join(','),
        "db.#{@database_name}.database"           => database_name,
        "db.#{@database_name}.driver"             => 'com.mysql.jdbc.Driver',
        "db.#{@database_name}.port"               => '3306',
        "db.#{@database_name}.username"           => mysql_username(dependent),
        "db.#{@database_name}.password_hiera_key" =>
            "enc/#{dependent.environment.name}/#{dependent.application}/mysql_password"
    }
    config_params["db.#{@database_name}.read_only_cluster"] =
        all_servers(fabric).join(",") unless all_servers(fabric).empty?
    config_params
  end

  def config_to_fulfil_requirement(dependent, hosts)
    config_params = {
        "db.#{@database_name}.hostname"           => hosts.map { |server| server.prod_fqdn }.join(','),
        "db.#{@database_name}.database"           => database_name,
        "db.#{@database_name}.driver"             => 'com.mysql.jdbc.Driver',
        "db.#{@database_name}.port"               => '3306',
        "db.#{@database_name}.username"           => mysql_username(dependent),
        "db.#{@database_name}.password_hiera_key" =>
            "enc/#{dependent.environment.name}/#{dependent.application}/mysql_password"
    }
    config_params["db.#{@database_name}.read_only_cluster"] =
        hosts.map { |server| server.prod_fqdn }.join(",") unless hosts.empty?
    config_params
  end
end
