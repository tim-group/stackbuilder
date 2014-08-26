require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::MongoDBServer < Stacks::MachineDef

  attr_accessor :arbiter, :backup
  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
    @arbiter = false
    @backup = false
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def to_enc()
    {
      'role::mongodb_server' => {
        'application' => @virtual_service.application,
        'arbiter'     => @arbiter,
        'backup'      => @backup
       }
    }
  end
end

