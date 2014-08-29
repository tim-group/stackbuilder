require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

module Stacks::MysqlCluster
  def self.extended(object)
    object.configure()
  end

  attr_accessor :database_name, :application

  def configure()
  end

  def clazz
    return 'mysqlcluster'
  end

  def config_params
    # This is where we can specify config params we want to spit out for config.properties
    # Not currently used as we need to think about how to standardise the application configuration
    []
    # example: [ [ 'db.config' = database_name ] ]
  end
end
