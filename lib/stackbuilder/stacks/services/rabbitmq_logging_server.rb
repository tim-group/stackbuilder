require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::RabbitMqLoggingServer < Stacks::MachineDef
  attr_reader :rabbitmq_logging_cluster

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @rabbitmq_logging_cluster = virtual_service
  end

  def stackname
    @rabbitmq_logging_cluster.name
  end

  def to_enc
  end
end
