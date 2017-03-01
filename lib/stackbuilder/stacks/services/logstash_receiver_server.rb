require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::LogstashReceiverServer < Stacks::MachineDef
  attr_reader :logstash_cluster

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @logstash_cluster = virtual_service
  end

  def stackname
    @logstash_cluster.name
  end

  def to_enc
    enc = super()

    rabbitmq_config = @logstash_cluster.rabbitmq_config

    enc.merge!('role::logstash_receiver' => {
                 'rabbitmq_logging_username'     => rabbitmq_config.username,
                 'rabbitmq_logging_password_key' => rabbitmq_config.password_hiera_key,
                 'rabbitmq_logging_exchange'     => @logstash_cluster.exchange,
                 'rabbitmq_logging_hosts'        => @logstash_cluster.rabbitmq_logging_hosts
               })
    enc
  end
end
