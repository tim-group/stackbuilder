require 'stackbuilder/stacks/namespace'

module Stacks::Services::ElasticsearchCluster
  include Stacks::Services::AppService

  def self.extended(object)
    object.configure
  end

  attr_accessor :cluster_name

  def configure
    @cluster_name = @name
    @application = 'ElasticsearchApp'
    @instances = 3
    @jvm_args = '-Xmx8g -Xms8g -XX:+UseParNewGC -XX:+UseConcMarkSweepGC -XX:CMSInitiatingOccupancyFraction=75' \
                ' -XX:+UseCMSInitiatingOccupancyOnly -XX:+HeapDumpOnOutOfMemoryError -XX:+DisableExplicitGC'
  end
end
