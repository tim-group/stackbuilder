require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::KibanaServer < Stacks::MachineDef
  attr_reader :kibana_cluster

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @kibana_cluster = virtual_service
  end

  def stackname
    @kibana_cluster.name
  end

  def to_enc
    enc = super()

    enc.merge!('role::kibana' => {
                 'elasticsearch_cluster_address' => @kibana_cluster.elasticsearch_data_address(@fabric),
                 'loadbalancer_hosts'            => @kibana_cluster.dependant_load_balancer_fqdns(location),
                 'prod_vip_fqdn'                 => @kibana_cluster.vip_fqdn(:prod, fabric)
               })
    enc
  end
end
