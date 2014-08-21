require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::MongoDBServer < Stacks::MachineDef

  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def to_enc()
    {
      'role::mongodb_server' => {
        'application' => @virtual_service.application
       }
    }
  end
end

