require 'stackbuilder/stacks/namespace'

class Stacks::Services::LoadBalancer < Stacks::MachineDef
  attr_accessor :virtual_router_id
  attr_reader :location

  def bind_to(environment)
    super(environment)
    @virtual_router_id = environment.options[:lb_virtual_router_id] || 1
  end

  def to_enc
    enc = super()
    enc['role::loadbalancer'] = {
      'virtual_router_id' => virtual_router_id,
      'virtual_servers'   => @virtual_service.loadbalancer_config_hash(@location, @fabric)
    }
    enc
  end
end
