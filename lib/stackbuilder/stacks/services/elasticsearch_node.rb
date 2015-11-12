require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ElasticsearchNode < Stacks::MachineDef
  def initialize(virtual_service, index)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)

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
                 'cluster_nodes' =>  @virtual_service.children.map(&:prod_fqdn)
               })
    enc
  end
end
