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

  def stackname
    @elasticsearch_cluster.name
  end

  def role?(role)
    @role == role
  end

  def to_enc
    enc = super()
    minimum_master_nodes = ((@elasticsearch_cluster.nodes_with_role(:master).size / 2) + 1).floor
    masters = @elasticsearch_cluster.nodes_with_role(:master).reject { |fqdn| fqdn == prod_fqdn }
    vip_fqdn = @elasticsearch_cluster.vip_fqdn(:prod, fabric)
    marvel_target = @elasticsearch_cluster.marvel_target_vip
    cluster = @elasticsearch_cluster.cluster_name(environment)

    enc.merge!("role::elasticsearch::#{@role}" => {
                 'version'              => @version,
                 'master_nodes'         => masters,
                 'minimum_master_nodes' => minimum_master_nodes,
                 'cluster_name'         => cluster,
                 'vip_fqdn'             => vip_fqdn
               })
    enc["role::elasticsearch::#{@role}"].merge!('marvel_target' => marvel_target) unless marvel_target.nil?
    enc
  end
end
