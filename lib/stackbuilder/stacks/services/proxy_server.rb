require 'stackbuilder/stacks/namespace'

class Stacks::Services::ProxyServer < Stacks::MachineDef
  attr_reader :disable_enc
  attr_reader :location

  def initialize(virtual_service, index, networks = [:mgmt, :prod], location = :primary_site)
    super(virtual_service.name + "-" + index, networks, location)
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
      service_resources = Hash[@virtual_service.downstream_services(location)]
      {
        'role::proxyserver' => {
          'default_ssl_cert' => @virtual_service.cert,
          'prod_vip_fqdn'    => @virtual_service.vip_fqdn(:prod, location),
          'vhosts'           => service_resources,
          'environment'      => environment.name,
        },
      }
    end
  end
end
