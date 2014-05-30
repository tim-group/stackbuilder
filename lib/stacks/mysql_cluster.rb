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
end
