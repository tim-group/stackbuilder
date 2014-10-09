require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::RabbitMQServer < Stacks::MachineDef
  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def vip_fqdn(net)
    return @virtual_service.vip_fqdn(net)
  end

  def to_enc()
    enc = {
      'role::rabbitmq_server' => {
        'cluster_nodes' =>  @virtual_service.realserver_prod_fqdns.map { |fqdn| fqdn.split('.')[0] },
        'vip_fqdn' => vip_fqdn(:prod),
       },
       'server::default_new_mgmt_net_local' => nil
    }
    if @virtual_service.dependant_instances and ! @virtual_service.dependant_instances.nil? and @virtual_service.dependant_instances != []
      enc['role::rabbitmq_server'].merge!({
        'dependant_instances' => @virtual_service.dependant_instances,
        'dependencies' => @virtual_service.dependency_config,
      })
    end
    enc
  end
end

