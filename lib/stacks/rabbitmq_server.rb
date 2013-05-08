require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::RabbitMQServer < Stacks::MachineDef
  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end
  def to_enc()
    {
      'role::rabbitmq_server_application' => {
        "cluster_nodes" =>  @virtual_service.realserver_prod_fqdns.map { |fqdn| fqdn.split('.')[0] }
       }
    }
  end
end

