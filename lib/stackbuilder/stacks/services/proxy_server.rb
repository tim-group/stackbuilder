require 'stackbuilder/stacks/namespace'

class Stacks::Services::ProxyServer < Stacks::MachineDef
  attr_reader :disable_enc
  attr_reader :location

  def initialize(virtual_service, base_hostname, environment, site, _role)
    super(virtual_service, base_hostname, environment, site)
    @disable_enc = false
  end

  def disable_enc
    @disable_enc = true
  end

  def to_enc
    if @disable_enc
      {}
    else
      service_resources = Hash[@virtual_service.downstream_services(location)]
      enc = super()
      enc.merge!('role::proxyserver' => {
                   'default_ssl_cert' => @virtual_service.cert,
                   'prod_vip_fqdn'    => @virtual_service.vip_fqdn(:prod, fabric),
                   'vhosts'           => service_resources,
                   'environment'      => environment.name
                 })
      enc
    end
  end
end
