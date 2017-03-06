require 'stackbuilder/stacks/namespace'

module Stacks::Services::ElasticsearchMasterCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :instances
  attr_accessor :ports

  def configure
    @ports = [9300]
    @instances = 3
  end

  def elasticsearch_data_hosts
    virtual_services_that_depend_on_me.select do |service|
      service.is_a?(Stacks::Services::ElasticsearchDataCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end
end
