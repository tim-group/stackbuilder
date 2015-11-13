require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ElasticsearchNode < Stacks::Services::AppServer
  def initialize(virtual_service, index, networks = [:mgmt, :prod], location = :primary_site)
    @virtual_service = virtual_service
    super(virtual_service, index, networks, location)

    @ram = '16777216' # 16GB
    @vcpus = '4'

    storage = {
      '/tmp' => {
        :type       => 'os',
        :size       => '10G',
        :persistent => false
      },
      '/mnt/data' => {
        :type       => 'data',
        :size       => '10G',
        :persistent => true
      }
    }
    modify_storage(storage)
  end

  def to_enc
    enc = super()
    enc.merge!('role::elasticsearch_node' => {
                 'cluster_nodes' =>  @virtual_service.children.map(&:prod_fqdn),
                 'cluster_name' =>  @virtual_service.cluster_name
               })
    enc['role::http_app'].merge!('dependencies' => {
                                   'elasticsearch_cluster_nodes' => @virtual_service.children.map(&:prod_fqdn)
                                 })
    enc['role::http_app'].merge!('elasticsearch_cluster_name' => @virtual_service.cluster_name)
    enc
  end
end
