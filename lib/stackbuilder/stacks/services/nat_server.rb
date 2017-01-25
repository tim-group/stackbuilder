require 'stackbuilder/stacks/namespace'

class Stacks::Services::NatServer < Stacks::MachineDef
  attr_reader :virtual_router_ids

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @nat_cluster = virtual_service
    @networks = [:mgmt, :prod, :front]
    @virtual_router_ids = {}
  end

  def bind_to(environment)
    super(environment)
    @virtual_router_ids[:front] = environment.options[:nat_front_virtual_router_id] || 105
    @virtual_router_ids[:prod] = environment.options[:nat_prod_virtual_router_id] || 106
  end

  def to_enc
    fail 'Nat servers do not support secondary_site' if @nat_cluster.enable_secondary_site
    enc = super
    rules = {
      'SNAT' => @nat_cluster.snat_rules,
      'DNAT' => @nat_cluster.dnat_rules
    }
    enc.merge('role::natserver' => {
                'rules'                   => rules,
                'front_virtual_router_id' => virtual_router_ids[:front],
                'prod_virtual_router_id'  => virtual_router_ids[:prod]
              })
  end
end
