require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ElasticsearchNode < Stacks::MachineDef
  attr_accessor :role

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @version = '2.3.3'

    data_storage = {
      '/mnt/data' => {
        :type       => 'data',
        :size       => @virtual_service.data_storage,
        :persistent => true
      }
    }
    modify_storage(data_storage) if role?(:data)
  end

  def stackname
    @virtual_service.name
  end

  def role?(role)
    @role == role
  end

  def to_enc
    enc = super()
    minimum_master_nodes = ((@virtual_service.nodes_with_role(:master).size / 2) + 1).floor
    masters = @virtual_service.nodes_with_role(:master).reject { |fqdn| fqdn == prod_fqdn }
    vip_fqdn = @virtual_service.vip_fqdn(:prod, fabric)
    marvel_target = @virtual_service.marvel_target_vip
    cluster = @virtual_service.cluster_name(environment)

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
