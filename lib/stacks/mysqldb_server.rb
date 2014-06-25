require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::MysqlDBServer < Stacks::MachineDef

  attr_accessor :database_name, :application, :data_size
  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    @allow_destroy = false
    super(virtual_service.name + "-" + index)
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end


  def allow_destroy()
    @allow_destroy = true
  end


  def to_spec()
    spec = super
    spec[:disallow_destroy] = true unless @allow_destroy
    spec
  end

  def to_enc()
    {
      'role::databaseserver' => {
        'application'              => @virtual_service.application,
        'environment'              => environment.name,
        'database_name'            => @virtual_service.database_name,
        'restart_on_config_change' => true,
      }
    }
  end

  def storage
    return super if data_size.nil?
    data_storage = {
      '/var/lib/mysql'.to_sym =>  {
        :type => 'data',
        :size => data_size
      }
    }
    return data_storage.merge(super)
  end
end

