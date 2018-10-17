require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ElasticsearchDataServer < Stacks::MachineDef
  attr_reader :logstash_cluster

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @elasticsearch_cluster = virtual_service
    @node_attrs = {}
  end

  def stackname
    @elasticsearch_cluster.name
  end

  def add_node_attribute(attr_name, attr_setting)
    @node_attrs[attr_name] = attr_setting
  end

  def to_enc
    enc = super()

    allowed_hosts = @virtual_service.dependant_instance_fqdns(location, [:prod], false)
    allowed_hosts += @virtual_service.allowed_hosts

    enc.merge!('role::elasticsearch_data' => {
                 'elasticsearch_master_hosts'     => @elasticsearch_cluster.elasticsearch_master_hosts,
                 'other_elasticsearch_data_hosts' => @elasticsearch_cluster.other_elasticsearch_data_hosts(mgmt_fqdn),
                 'kibana_hosts'                   => @elasticsearch_cluster.kibana_hosts,
                 'loadbalancer_hosts'             => @elasticsearch_cluster.dependant_load_balancer_fqdns(location),
                 'logstash_indexer_hosts'         => @elasticsearch_cluster.logstash_indexer_hosts,
                 'logstash_receiver_hosts'         => @elasticsearch_cluster.logstash_receiver_hosts,
                 'prod_vip_fqdn'                  => @elasticsearch_cluster.vip_fqdn(:prod, fabric),
                 'minimum_master_nodes'           => @elasticsearch_cluster.elasticsearch_minimum_master_nodes,
                 'node_attrs'                     => @node_attrs,
                 'allowed_hosts'                  => allowed_hosts.uniq.sort
               })
    enc
  end
end
