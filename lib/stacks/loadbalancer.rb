require 'stacks/namespace'

class Stacks::LoadBalancer < Stacks::MachineDef

  attr_accessor :virtual_router_id

  def initialize(virtual_service, index, &block)
    @virtual_service = virtual_service
    super(virtual_service.name + "-" + index)
  end

  def bind_to(environment)
    super(environment)
    @virtual_router_id = environment.options[:lb_virtual_router_id] || 1
  end

  def to_enc
    enc = super()
    virtual_services_hash = {}
    @virtual_service.virtual_services(Stacks::AbstractVirtualService).map do |virtual_service|
      virtual_services_hash.merge! virtual_service.to_loadbalancer_config
    end
    enc['role::loadbalancer'] = {
      'virtual_router_id' => self.virtual_router_id,
      'virtual_servers' => virtual_services_hash
    }
    enc
   end
end
