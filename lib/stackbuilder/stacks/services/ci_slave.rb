require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::CiSlave < Stacks::MachineDef
  attr_accessor :node_labels
  attr_accessor :allow_matrix_host
  attr_accessor :spectre_patches

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @node_labels = []
    @allow_matrix_host = nil
    @networks = [:mgmt]
    @spectre_patches = nil
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
               'server' => {
                 'minimal' => true
               })

    enc['server']['spectre_patches'] = @spectre_patches if @spectre_patches
    enc
  end
end
