require 'stacks/namespace'

class Stacks::ProxyServer < Stacks::MachineDef
  attr_reader :virtual_service

  def initialize(virtual_service, index)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    service_resources = Hash[virtual_service.downstream_services()]
    {'role::proxyserver' => {
        'prod_vip_fqdn' => self.virtual_service.vip_fqdn,
        'vhosts'  => service_resources
      }
    }
  end
end
