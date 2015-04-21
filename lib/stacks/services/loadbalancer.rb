require 'stacks/namespace'

class Stacks::Services::LoadBalancer < Stacks::MachineDef
  attr_accessor :virtual_router_id

  def initialize(virtual_service, index, networks = [:mgmt, :prod], location = :primary_site)
    super(virtual_service.name + "-" + index, networks, location)
    @virtual_service = virtual_service
  end

  def bind_to(environment)
    super(environment)
    @virtual_router_id = environment.options[:lb_virtual_router_id] || 1
  end

  def to_enc
    enc = super()
    virtual_services_hash = {}
    @virtual_service.virtual_services(Stacks::Services::AbstractVirtualService).map do |virtual_service|
      if virtual_service.fabric == fabric
        virtual_services_hash.merge! virtual_service.to_loadbalancer_config
      end
    end
    enc['role::loadbalancer'] = {
      'virtual_router_id' => virtual_router_id,
      'virtual_servers' => virtual_services_hash
    }
    enc
  end
end
