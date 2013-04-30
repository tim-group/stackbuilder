require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::RabbitMQServer < Stacks::MachineDef
  def initialize(virtual_service, index, &block)
    super(virtual_service.name + "-" + index)
  end
  def to_enc()
    {
      'role::rabbitmq_server_application' => { }
    }
  end
end

