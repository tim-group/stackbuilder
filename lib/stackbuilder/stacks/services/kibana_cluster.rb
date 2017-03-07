require 'stackbuilder/stacks/namespace'

module Stacks::Services::KibanaCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :instances
  attr_accessor :ports

  def configure
    @ports = [8000]
    @instances = 2
  end

  def elasticsearch_data_address(fabric)
    addrs = virtual_services_that_i_depend_on.select do |service|
      service.is_a?(Stacks::Services::ElasticsearchDataCluster)
    end.map do |service|
      service.vip_fqdn(:prod, fabric)
    end.flatten.sort

    fail('Kibana cluster can only depend on one elasticsearch data cluster') if addrs.length > 1
    addrs.first
  end
end
