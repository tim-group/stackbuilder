require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::MysqlDBServer < Stacks::MachineDef

  attr_accessor :database_name, :application
  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def to_enc()
    {
      'role::databaseserver' => {
        'application'              => self.application,
        'environment'              => environment.name,
        'database_name'            => self.database_name,
        'restart_on_config_change' => true,  
      }

    }
  end
end

