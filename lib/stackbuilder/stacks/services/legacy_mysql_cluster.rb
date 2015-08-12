require 'stackbuilder/stacks/namespace'
require 'uri'

module Stacks::Services::LegacyMysqlCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :database_name, :application, :instances

  def configure
    @database_name = ''
    @application = false
    @instances = 1
  end

  def clazz
    'mysqlcluster'
  end

  def mysqldb_server
    fail 'MySQL cluster does not currently support more than 1 server' if children.size > 1
    children.first
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
      "db.#{@database_name}.hostname"           => mysqldb_server.prod_fqdn,
      "db.#{@database_name}.database"           => database_name,
      "db.#{@database_port}.port"               => '3306',
      "db.#{@database_name}.username"           => "#{dependant.application}",
      "db.#{@database_name}.password_hiera_key" =>
        "enc/#{dependant.environment.name}/#{dependant.application}/mysql_password"
    }
  end
end
