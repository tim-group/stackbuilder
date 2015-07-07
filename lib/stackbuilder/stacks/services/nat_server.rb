require 'stackbuilder/stacks/namespace'

class Stacks::Services::NatServer < Stacks::MachineDef
  attr_reader :virtual_router_ids

  def initialize(virtual_service, index, networks = [:mgmt, :prod, :front], location = :primary_site)
    networks = [:mgmt, :prod, :front]
    super(virtual_service.name + "-" + index, networks, location)
    @virtual_service = virtual_service
    @virtual_router_ids = {}
  end

  def bind_to(environment)
    super(environment)
    @virtual_router_ids[:front] = environment.options[:nat_front_virtual_router_id] || 105
    @virtual_router_ids[:prod] = environment.options[:nat_prod_virtual_router_id] || 106
  end

  def to_enc
    fail 'Nat servers do not support secondary_site' if @virtual_service.enable_secondary_site
    enc = super
    rules = {
      'SNAT' => @virtual_service.snat_rules,
      'DNAT' => @virtual_service.dnat_rules
    }
    enc.merge('role::natserver' => {
                'rules'                   => rules,
                'front_virtual_router_id' => virtual_router_ids[:front],
                'prod_virtual_router_id'  => virtual_router_ids[:prod]
              })
  end
end
