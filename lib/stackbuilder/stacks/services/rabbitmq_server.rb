require 'stackbuilder/stacks/namespace'

class Stacks::Services::RabbitMQServer < Stacks::MachineDef
  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @rabbitmq_cluster = virtual_service
  end

  def to_enc
    enc = super()
    enc.merge!('role::rabbitmq_server' => {
                 'cluster_nodes' =>  @rabbitmq_cluster.cluster_nodes(location),
                 'vip_fqdn' => @rabbitmq_cluster.vip_fqdn(:prod, fabric)
               })

    dependant_instances = @rabbitmq_cluster.dependant_instance_fqdns(location)
    dependant_instances.concat(@rabbitmq_cluster.children.map(&:prod_fqdn)).sort
    dependant_instances.delete prod_fqdn

    if !dependant_instances.nil? && dependant_instances != []
      enc['role::rabbitmq_server'].merge!('dependant_instances' => dependant_instances,
                                          'dependencies'        => @rabbitmq_cluster.dependency_config(fabric, self),
                                          'dependant_users'     => @rabbitmq_cluster.dependant_users,
                                          'rabbit_users'        => [])
    end

    enc
  end
end
