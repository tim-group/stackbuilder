require 'stackbuilder/stacks/namespace'

module Stacks::Services::LogstashIndexerCluster
  include Stacks::Services::RabbitMqDependent

  def self.extended(object)
    object.configure
  end

  attr_accessor :instances
  attr_accessor :ports
  attr_accessor :exchange

  def configure
    @ports = [5044]
    @instances = 2
    @exchange = 'logging'
  end

  def rabbitmq_config
    create_rabbitmq_config('logstash_indexer')
  end

  def rabbitmq_logging_hosts
    virtual_services_that_i_depend_on.select do |service|
      service.is_a?(Stacks::Services::RabbitMqLoggingCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end

  def dependent_elasticsearch_data_clusters
    virtual_services_that_i_depend_on.select do |service|
      service.is_a?(Stacks::Services::ElasticsearchDataCluster)
    end
  end

  def xpack_monitoring_elasticsearch_url(fabric)
    addrs = dependent_elasticsearch_data_clusters.select(&:is_xpack_monitoring_destination).map! do |service|
      service.vip_fqdn(:prod, fabric)
    end.flatten.sort

    fail('Logstash indexer cluster can only have one dependent elasticsearch cluster configured as the xpack_monitoring_destination') if addrs.length > 1
    addrs.first
  end

  def elasticsearch_clusters(fabric)
    clusters = {}
    dependent_elasticsearch_data_clusters.each do |service|
      clusters[service.vip_fqdn(:prod, fabric)] = service.children.map(&:prod_fqdn)
    end
    clusters.each do |_cluster, hosts|
      hosts.sort!
    end
    clusters
  end

  def logstash_receiver_hosts # (dependent_machine_site)
    virtual_services_that_i_depend_on.select do |service|
      service.is_a?(Stacks::Services::LogstashReceiverCluster)
    end.map do |service|
      service.children.map(&:mgmt_fqdn)
    end.flatten.sort
  end
end
