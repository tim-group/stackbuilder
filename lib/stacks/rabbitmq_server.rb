require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::RabbitMQServer < Stacks::MachineDef
  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def to_enc()
    {
      'role::rabbitmq_server' => {
        'cluster_nodes' =>  @virtual_service.realserver_prod_fqdns.map { |fqdn| fqdn.split('.')[0] },
        'vip_fqdn' => vip_fqdn,
       },
       'server::default_new_mgmt_net_local' => nil
    }
  end
end

