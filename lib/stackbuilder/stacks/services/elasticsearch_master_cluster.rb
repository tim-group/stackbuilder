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

  def other_elasticsearch_master_hosts(this_servers_hostname)
    children.select do |child|
      child.mgmt_fqdn != this_servers_hostname
    end.map(&:prod_fqdn).flatten.sort
  end

  def elasticsearch_minimum_master_nodes
    (children.length.to_f / 2).ceil
  end
end
