require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::LogstashReceiverServer < Stacks::MachineDef
  attr_accessor :role

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
  end

  def stackname
    @virtual_service.name
  end

  def to_enc
    enc = super()

    rabbitmq_config = @virtual_service.get_rabbitmq_config

    enc.merge!('role::logstash_receiver' => {
                 'rabbitmq_logging_username' => rabbitmq_config.username,
                 'rabbitmq_logging_password_key' => rabbitmq_config.password_hiera_key
               })
    enc
  end
end
