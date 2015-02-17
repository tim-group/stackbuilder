require 'stacks/namespace'

class Stacks::ProxyServer < Stacks::MachineDef
  attr_reader :virtual_service, :disable_enc

  def initialize(virtual_service, index)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
    @disable_enc = false
  end

  def bind_to(environment)
    super(environment)
  end

  def disable_enc
    @disable_enc = true
  end

  def to_enc
    if @disable_enc
      {}
    else
      service_resources = Hash[virtual_service.downstream_services]
      {
        'role::proxyserver' => {
          'default_ssl_cert' => @virtual_service.cert,
          'prod_vip_fqdn'    => @virtual_service.vip_fqdn(:prod),
          'vhosts'           => service_resources,
          'environment'      => environment.name
        }
      }
    end
  end
end
