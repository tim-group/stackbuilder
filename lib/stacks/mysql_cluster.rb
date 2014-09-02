require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

module Stacks::MysqlCluster
  def self.extended(object)
    object.configure()
  end

  attr_accessor :database_name

  def configure()
    @database_name = ''
  end

  def clazz
    return 'mysqlcluster'
  end

  def mysqldb_server
    raise 'MySQL cluster does not currently support more than 1 server' if children.size > 1
    mysqldb_server = children.first
  end

  def dependant_instance_mysql_rights()
    rights = {}
    dependant_services.each do |service|
      service.children.each do |dependant|
        rights.merge!({
          'mysql_hacks::application_rights_wrapper' => {
           "#{service.application}@#{dependant.prod_fqdn}" => {
              'database'            => "#{database_name}",
              'password_hiera_key'  => "enc/#{service.environment.name}/#{service.application}/password"
            }
          }
        })
      end
    end
    rights
  end

  def config_params(dependant)
    # This is where we can provide config params to App servers (only) to put into their config.properties
    [
      ["db.#{@database_name}.hostname", mysqldb_server.prod_fqdn ],
      ["db.#{@database_name}.database", database_name],
      ["db.#{@database_name}.username", "#{dependant.application}"],
      ["db.#{@database_name}.password_hiera_key", "enc/#{dependant.environment.name}/#{dependant.application}/password"],
    ]
  end

end
