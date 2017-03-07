require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ElasticsearchDataServer < Stacks::MachineDef
  attr_reader :logstash_cluster

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @elasticsearch_cluster = virtual_service
  end

  def stackname
    @elasticsearch_cluster.name
  end

  def to_enc
    enc = super()

    enc.merge!('role::elasticsearch_data' => {
                 'elasticsearch_master_hosts' => @elasticsearch_cluster.elasticsearch_master_hosts,
                 'kibana_hosts' => @elasticsearch_cluster.kibana_hosts,
                 'loadbalancer_hosts' => @elasticsearch_cluster.dependant_load_balancer_fqdns(location),
                 'logstash_indexer_hosts' => @elasticsearch_cluster.logstash_indexer_hosts
               },
               'server::default_new_mgmt_net_local' => nil)
    enc
  end
end
