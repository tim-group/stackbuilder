require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::ElasticSearchNode < Stacks::MachineDef
  attr_reader :machine_set
  def initialize(server_group, index)
    @machine_set = server_group
    super(server_group.name + "-" + index, [:prod, :mgmt])
    self
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    enc = super()
    enc.merge!('role::elasticsearch_node' => {
                 'cluster_nodes' =>  machine_set.definitions.values.map(&:prod_fqdn)
               })
    enc
  end
end
