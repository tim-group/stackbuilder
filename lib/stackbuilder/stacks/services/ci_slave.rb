require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::CiSlave < Stacks::MachineDef
  attr_accessor :mysql_version
  attr_accessor :node_labels
  attr_accessor :allow_matrix_host

  def initialize(server_group, index)
    super(server_group.name + '-' + index, [:mgmt])
    @node_labels = []
    @allow_matrix_host = nil
    self
  end

  def availability_group
    nil
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    enc = super()
    enc.merge!('role::cinode_precise' => {
                 'node_labels'   => @node_labels.join(' '),
                 'allow_matrix_host' => @allow_matrix_host
               })
    enc
  end
end
