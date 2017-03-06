require 'stackbuilder/stacks/namespace'

module Stacks::Services::ElasticsearchDataCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :instances
  attr_accessor :ports

  def configure
    @ports = [9200]
    @instances = 2
  end

  def logstash_indexer_hosts
    virtual_services_that_depend_on_me.select do |service|
      service.is_a?(Stacks::Services::LogstashIndexerCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end

  def elasticsearch_master_hosts
    virtual_services_that_i_depend_on.select do |service|
      service.is_a?(Stacks::Services::ElasticsearchMasterCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end
end
