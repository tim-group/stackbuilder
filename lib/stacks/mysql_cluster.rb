require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

module Stacks::MysqlCluster
  def self.extended(object)
    object.configure()
  end

  attr_accessor :database_name, :application, :instances

  def configure()
    @database_name = ''
    @application = false
    @master_instances = 1
    @slave_instances = 1
    @backup_instances = 1

  end

  def instantiate_machine(name, type, index, environment)
    server = @type.new(self, type, index, &@config_block)
    server.group = groups[i%groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    @definitions[server.name] = server
    server
  end

  def instantiate_machines(environment)
    i = 0
    @master_instances.times do
      index = sprintf("%03d",i+=1)
      instantiate_machine(name, :master, index, environment)
    end
    @slave_instances.times do
      index = sprintf("%03d",i+=1)
      instantiate_machine(name, :slave, index, environment)
    end
    @backup_instances.times do
      index = sprintf("%03d",i+=1)
      instantiate_machine(name, :backup, index, environment)
    end
  end

  def clazz
    return 'mysqlcluster'
  end

  def masters
    masters = children.reject { |mysql_server| !mysql_server.master? }
    raise "No masters were not found! #{children}" if masters.empty?
    #Only return the first master (multi-master support not implemented)
    [masters.first.prod_fqdn]
  end

  def dependant_instance_mysql_rights()
    rights = {
      'mysql_hacks::application_rights_wrapper' => { 'rights' => {}}
    }
    dependant_services.each do |service|
      service.children.each do |dependant|
        rights['mysql_hacks::application_rights_wrapper']['rights'].merge!({
          "#{service.application}@#{dependant.prod_fqdn}/#{database_name}" => {
            'password_hiera_key'  => "enc/#{service.environment.name}/#{service.application}/mysql_password"
          }
        })
      end
    end
    rights
  end

  def config_params(dependant)
    # This is where we can provide config params to App servers (only) to put into their config.properties
    {
      "db.#{@database_name}.hostname"           => masters.join(','),
      "db.#{@database_name}.database"           => database_name,
      "db.#{@database_name}.username"           => dependant.application,
      "db.#{@database_name}.password_hiera_key" => "enc/#{dependant.environment.name}/#{dependant.application}/mysql_password",
    }
  end

end
