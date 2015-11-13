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
    @jvm_args = '-Xmx8g -Xms8g'
  end
end
