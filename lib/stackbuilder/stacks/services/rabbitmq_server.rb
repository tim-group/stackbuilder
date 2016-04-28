require 'stackbuilder/stacks/namespace'

class Stacks::Services::RabbitMQServer < Stacks::MachineDef
  def initialize(rabbitmq_cluster, index, networks = [:mgmt, :prod], location = :primary_site)
    super(rabbitmq_cluster.name + "-" + index, networks, location)
    @rabbitmq_cluster = rabbitmq_cluster
  end

  def to_enc
    enc = super()
    enc.merge!('role::rabbitmq_server' => {
                 'cluster_nodes' =>  @rabbitmq_cluster.cluster_nodes(location),
                 'vip_fqdn' => @rabbitmq_cluster.vip_fqdn(:prod, fabric)
               },
               'server::default_new_mgmt_net_local' => nil)
    dependant_instances = @rabbitmq_cluster.dependant_instance_fqdns(location)
    dependant_instances.concat(@rabbitmq_cluster.children.map(&:prod_fqdn)).sort
    dependant_instances.delete prod_fqdn

    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::rabbitmq_server'].merge!('dependant_instances' => dependant_instances,
                                          'dependencies' => @rabbitmq_cluster.dependency_config(fabric))
    end
    enc
  end
end
