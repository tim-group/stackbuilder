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
end
