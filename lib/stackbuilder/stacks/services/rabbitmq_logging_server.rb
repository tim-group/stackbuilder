require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::RabbitMqLoggingServer < Stacks::MachineDef
  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
  end

  def stackname
    @virtual_service.name
  end

  def to_enc
  end
end
