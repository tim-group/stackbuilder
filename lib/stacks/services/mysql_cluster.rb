require 'stacks/namespace'

module Stacks::Services::MysqlCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :database_name, :master_instances, :slave_instances, :backup_instances, :charset

  def configure
    @database_name = ''
    @master_instances = 1
    @slave_instances = 1
    @backup_instances = 1
    @charset = 'utf8'
  end

  def instantiate_machine(name, type, index, environment, location)
    server_name = "#{name}-#{index}"
    server_name = "#{name}#{type}-#{index}" if type == :backup
    server = @type.new(server_name, self, type, location)
    server.group = groups[i % groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    # FIXME: Is this required?
    @definitions[server_name] = server
    server
  end

  def instantiate_machines(environment)
    fail 'MySQL clusters do not currently support enable_secondary_site' if @enable_secondary_site
    i = 0
    @master_instances.times do
      instantiate_machine(name, :master, sprintf("%03d", i += 1), environment, :primary_site)
    end
    @slave_instances.times do
      instantiate_machine(name, :slave, sprintf("%03d", i += 1), environment, :primary_site)
    end

    i = 0
    @backup_instances.times do
      instantiate_machine(name, :backup, sprintf("%03d", i += 1), environment, :secondary_site)
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
    # Only return the first master (multi-master support not implemented)
    [masters.first.prod_fqdn]
  end

  def secondary_servers
    children.select { |server| !server.master? && !server.backup? }.inject([]) do |slaves, server|
      slaves << server.prod_fqdn
      slaves
    end
  end

  def dependant_children_replication_mysql_rights(server)
    rights = {
      'mysql_hacks::replication_rights_wrapper' => { 'rights' => {} }
    }
    children.each do |dependant|
      next if dependant == server

      rights['mysql_hacks::replication_rights_wrapper']['rights'].merge!(
        "replicant@#{dependant.prod_fqdn}" => {
          'password_hiera_key' => "enc/#{dependant.environment.name}/#{database_name}/replication/mysql_password"
        })
    end
    rights
  end

  def dependant_instance_mysql_rights(location)
    rights = {
      'mysql_hacks::application_rights_wrapper' => { 'rights' => {} }
    }
    virtual_services_that_depend_on_me(location).each do |service|
      service.children.each do |dependant|
        rights['mysql_hacks::application_rights_wrapper']['rights'].
          merge!("#{service.application}@#{dependant.prod_fqdn}/#{database_name}" =>
                 { 'password_hiera_key' => "enc/#{service.environment.name}/#{service.application}/mysql_password" })
      end
    end
    rights
  end

  def config_params(dependant, _location)
    # This is where we can provide config params to App servers (only) to put into their config.properties
    {
      "db.#{@database_name}.hostname"           => master_servers.join(','),
      "db.#{@database_name}.database"           => database_name,
      "db.#{@database_name}.username"           => dependant.application,
      "db.#{@database_name}.password_hiera_key" =>
        "enc/#{dependant.environment.name}/#{dependant.application}/mysql_password",
      "db.#{@database_name}.secondary_hostnames" => secondary_servers.join(",")
    }
  end
end
