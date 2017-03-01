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
end
