require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ElasticsearchMasterServer < Stacks::MachineDef
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

    enc.merge!('role::elasticsearch_master' => {
                 'elasticsearch_data_hosts'         => @elasticsearch_cluster.elasticsearch_data_hosts,
                 'other_elasticsearch_master_hosts' => @elasticsearch_cluster.other_elasticsearch_master_hosts(mgmt_fqdn),
                 'minimum_master_nodes'             => @elasticsearch_cluster.elasticsearch_minimum_master_nodes
               },
               'server::default_new_mgmt_net_local' => nil)
    enc
  end
end
