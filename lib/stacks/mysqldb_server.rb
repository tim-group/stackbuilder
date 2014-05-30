require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::MysqlDBServer < Stacks::MachineDef

  attr_accessor :database_name, :application
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
    app = self.application
    db = self.database_name

    if (@virtual_service.application != nil and @virtual_service.database_name != nil)
      app = @virtual_service.application
      db = @virtual_service.database_name
    end

    {
      'role::databaseserver' => {
        'application'              => app,
        'environment'              => environment.name,
        'database_name'            => db,
        'restart_on_config_change' => true,
      }
    }
  end
end

