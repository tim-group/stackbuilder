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
                 'elasticsearch_cluster_address' => @kibana_cluster.elasticsearch_data_address(@fabric)
               },
               'server::default_new_mgmt_net_local' => nil)
    enc
  end
end
