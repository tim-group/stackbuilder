require 'stackbuilder/stacks/namespace'

module Stacks::Services::ElasticsearchCluster
  def self.extended(object)
    object.configure
  end

  def configure
    @cluster_name = 'elasticsearch'
    @instances = 3
  end

end
