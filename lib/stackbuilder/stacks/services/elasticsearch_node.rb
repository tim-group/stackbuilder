require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ElasticsearchNode < Stacks::MachineDef
  attr_accessor :role

  def initialize(base_hostname, _i, elasticsearch_cluster, role, location)
    super(base_hostname, [:mgmt, :prod], location)

    @elasticsearch_cluster = elasticsearch_cluster
    @role = role
    @version = '2.3.1'

    data_storage = {
      '/mnt/data' => {
        :type       => 'data',
        :size       => @elasticsearch_cluster.data_storage,
        :persistent => true
      }
    }
    modify_storage(data_storage) if role?(:data)
  end

  def role?(role)
    @role == role
  end

  def to_enc
    enc = super()
    minimum_master_nodes = (@elasticsearch_cluster.nodes_with_role(:master).size / 2) + 1
    masters = @elasticsearch_cluster.nodes_with_role(:master).reject { |fqdn| fqdn == prod_fqdn }
    all_nodes = @elasticsearch_cluster.all_nodes
    vip_fqdn = @elasticsearch_cluster.vip_fqdn(:prod, fabric)

    enc.merge!("role::elasticsearch::#{@role}" => {
                 'version' => @version,
                 'master_nodes'  => masters,
                 'minimum_master_nodes' => minimum_master_nodes,
                 'cluster_name'  =>  @elasticsearch_cluster.cluster_name,
                 'marvel_target' => @elasticsearch_cluster.marvel_target,
                 'all_nodes' => all_nodes,
                 'vip_fqdn' => vip_fqdn
               })
    enc
  end
end
