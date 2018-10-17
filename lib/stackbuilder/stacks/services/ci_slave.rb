require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::CiSlave < Stacks::MachineDef
  attr_accessor :node_labels
  attr_accessor :allow_matrix_host

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @node_labels = []
    @allow_matrix_host = nil
    @networks = [:mgmt]
  end

  def availability_group
    nil
  end

  def to_enc
    enc = super()
    enc.merge!('role::cinode' => {
                 'node_labels'   => @node_labels.join(' '),
                 'allow_matrix_host' => @allow_matrix_host
               },
               'server::default_new_mgmt_net_local' => {
                 'minimal' => true
               })
    enc
  end
end
