require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::MongoDBServer < Stacks::MachineDef
  attr_accessor :backup
  def initialize(mongodb_cluster, index)
    @mongodb_cluster = mongodb_cluster
    super(mongodb_cluster.name + "-" + index)
    @backup = false
  end

  def to_enc
    enc = super()
    enc.merge!('role::mongodb_server' => {
                 'application' => @mongodb_cluster.application
               })
    enc['mongodb::backup'] = { 'ensure' => 'present' } if @backup
    dependant_instances = @mongodb_cluster.dependant_instance_fqdns(location)
    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::mongodb_server'].merge!('dependant_instances' => dependant_instances,
                                         'dependencies' => @mongodb_cluster.dependency_config(fabric))
    end
    enc
  end
end
