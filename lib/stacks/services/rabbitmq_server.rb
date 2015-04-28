require 'stacks/namespace'

class Stacks::Services::RabbitMQServer < Stacks::MachineDef
  attr_reader :virtual_service

  def initialize(virtual_service, index, networks = [:mgmt, :prod], location = :primary_site)
    super(virtual_service.name + "-" + index, networks, location)
    @virtual_service = virtual_service
  end

  def to_enc
    enc = {
      'role::rabbitmq_server' => {
        'cluster_nodes' =>  @virtual_service.realserver_prod_fqdns(location).map { |fqdn| fqdn.split('.')[0] },
        'vip_fqdn' => @virtual_service.vip_fqdn(:prod, @location)
      },
      'server::default_new_mgmt_net_local' => nil
    }
    dependant_instances = @virtual_service.dependant_machine_def_fqdns
    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::rabbitmq_server'].merge!('dependant_instances' => dependant_instances,
                                          'dependencies' => @virtual_service.dependency_config(location))
    end
    enc
  end
end
