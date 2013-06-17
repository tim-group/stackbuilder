require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::ElasticSearchNode < Stacks::MachineDef
  def initialize(server_group, index, &block)
    super(server_group.name + "-" + index, [:mgmt])
    self
  end

 def bind_to(environment)
    super(environment)
  end

  def to_enc
    {
      'role::elasticsearch_node' => {
        'cluster_nodes' =>  @virtual_service.realserver_prod_fqdns
      }
    }
  end
end

