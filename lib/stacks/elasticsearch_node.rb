require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::ElasticSearchNode < Stacks::MachineDef
  attr_reader :machine_set
  def initialize(server_group, index, &block)
    @machine_set = server_group
    super(server_group.name + "-" + index, [:prod, :mgmt])
    self
  end

  def bind_to(environment)
    super(environment)
   end

  def to_enc
    {
      'role::elasticsearch_node' => {
        'cluster_nodes' =>  machine_set.definitions.values.map { |machinedef| machinedef.prod_fqdn }
      }
    }
  end
end
