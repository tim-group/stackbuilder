require 'stacks/namespace'
require 'stacks/ha'

class Stacks::SftpServer < Stacks::MachineDef

  include Stacks::HA

  attr_reader :virtual_service

  def initialize(virtual_service, index)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  def to_enc
    {
      'role::sftpserver' => {
        'vip_fqdn' => vip_fqdn,
        'env' => environment.name,
      }
    }
  end
end
