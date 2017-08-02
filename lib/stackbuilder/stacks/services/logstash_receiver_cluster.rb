require 'stackbuilder/stacks/namespace'

module Stacks::Services::LogstashReceiverCluster
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
    create_rabbitmq_config('logstash_receiver')
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

  def xpack_monitoring_elasticsearch_url
    addrs = dependent_elasticsearch_data_clusters.select(&:is_xpack_monitoring_destination).map do |service|
      service.vip_fqdn(:prod, service.environment.name)
    end.flatten.sort

    fail('Logstash recevier cluster can only have one dependent elasticsearch cluster configured as the xpack_monitoring_destination') if addrs.length > 1
    addrs.first
  end
end
