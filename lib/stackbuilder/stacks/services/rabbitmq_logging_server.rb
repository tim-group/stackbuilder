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
    enc = super()

    dependant_instances = @rabbitmq_logging_cluster.dependant_instance_fqdns(location)
    dependant_instances.concat(@rabbitmq_logging_cluster.children.map(&:prod_fqdn)).sort
    dependant_instances.delete prod_fqdn

    enc.merge!('role::rabbitmq_logging' => {
                 'cluster_nodes'       =>  @rabbitmq_logging_cluster.cluster_nodes,
                 'dependant_instances' => dependant_instances,
                 'dependant_users'     => @rabbitmq_logging_cluster.dependant_users,
                 'shovel_destinations' => @rabbitmq_logging_cluster.shovel_destinations
               })
  end
end
