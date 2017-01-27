require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::MongoDBServer < Stacks::MachineDef
  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @ram = '4194304' # 4GB
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
      '/mnt/storage' => {
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
                 'database_name' => @virtual_service.database_name
               })
    enc['mongodb::backup'] = { 'ensure' => 'present' } if role_of?(:backup)
    dependant_instances = @virtual_service.children.map(&:prod_fqdn)
    dependant_instances.delete prod_fqdn
    dependant_users = {}
    if role_of?(:master)
      dependant_instances.concat(@virtual_service.dependant_instance_fqdns(location))
      dependant_users = @virtual_service.dependant_users
    end

    if dependant_instances && !dependant_instances.nil? && dependant_instances != []
      enc['role::mongodb_server'].merge!('dependant_instances' => dependant_instances.sort,
                                         'dependant_users'     => dependant_users,
                                         'dependencies'        => @virtual_service.dependency_config(fabric))
    end
    enc
  end
end
