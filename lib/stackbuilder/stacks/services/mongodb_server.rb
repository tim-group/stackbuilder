require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::MongoDBServer < Stacks::MachineDef
  def initialize(base_hostname, i, mongodb_cluster, role, location)
    index = sprintf("%03d", i)
    super(base_hostname, [:mgmt, :prod], location)
    @index = index
    @location = location
    @mongodb_cluster = mongodb_cluster
    @ram = '4194304' # 4GB
    @role = role
    @vcpus = '2'
    data_size = '350G'
    data_size = '5G' if role_of?(:arbiter)

    storage = {
      '/mnt/data' => {
        :type       => 'data',
        :size       => data_size,
        :persistent => true
      }
    }
    backup_storage = {
      '/var/backups' => {
        :type       => 'data',
        :size       => '458G',
        :persistent => true
      }
    }
    modify_storage(storage)
    modify_storage(backup_storage) if role_of?(:backup)
  end

  def role_of?(role)
    @role == role
  end

  def to_enc
    enc = super()
    enc.merge!('role::mongodb_server' => {
                 'database_name' => @mongodb_cluster.database_name
               })
    enc['mongodb::backup'] = { 'ensure' => 'present' } if role_of?(:backup)
    dependant_instances = @mongodb_cluster.children.map(&:prod_fqdn)
    dependant_instances.delete prod_fqdn
    dependant_users = {}
    if role_of?(:master)
      dependant_instances.concat(@mongodb_cluster.dependant_instance_fqdns(location)).sort
      dependant_users = @mongodb_cluster.dependant_users
    end

    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::mongodb_server'].merge!('dependant_instances' => dependant_instances,
                                         'dependant_users'     => dependant_users,
                                         'dependencies'        => @mongodb_cluster.dependency_config(fabric))
    end
    enc
  end
end
