require 'stackbuilder/stacks/namespace'

module Stacks::Services::ElasticsearchCluster
  include Stacks::Services::AppService

  def self.extended(object)
    object.configure
  end

  def configure
    @cluster_name = 'elasticsearch'
    @application = 'ElasticsearchApp'
    @instances = 3
    @jvm_args = '-Xmx8g -Xms8g'
  end
end
