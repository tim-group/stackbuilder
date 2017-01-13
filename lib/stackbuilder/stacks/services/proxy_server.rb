require 'stackbuilder/stacks/namespace'

class Stacks::Services::ProxyServer < Stacks::MachineDef
  attr_reader :disable_enc
  attr_reader :location

  def initialize(virtual_service, base_hostname, environment, site, _role)
    super(virtual_service, base_hostname, environment, site)
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
      enc = super()
      enc.merge!('role::proxyserver' => {
                   'default_ssl_cert' => @virtual_service.cert,
                   'prod_vip_fqdn'    => @virtual_service.vip_fqdn(:prod, fabric),
                   'vhosts'           => service_resources,
                   'environment'      => environment.name
                 })

      if @virtual_service.is_use_deployapp_enabled
        enc['role::proxyserver'].merge!(
          'participation_dependant_instances' => @virtual_service.dependant_load_balancer_fqdns(location),
          'cluster'                           => availability_group,
          'use_deployapp'                     => @virtual_service.use_deployapp
        )
      end

      enc
    end
  end
end
