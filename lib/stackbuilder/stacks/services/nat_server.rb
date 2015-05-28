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

  def find_nat_rules(location)
    rules = []
    environment.accept do |node|
      unless node.environment.contains_node_of_type?(Stacks::Services::NatServer) && environment != node.environment
        if node.respond_to? :nat
          if node.nat
            if location == :primary_site
              rules =  rules.concat node.nat_rules(location)
            else
              if node.respond_to?(:secondary_site?)
                rules =  rules.concat node.nat_rules(location) if node.secondary_site?
              end
            end
          end
        end
      end
    end
    rules
  end

  def to_enc
    enc = super
    rules = {}

    snat = {
      'SNAT' => {
        'prod' => {
          'to_source' => "nat-vip.front.#{environment.options[location]}.net.local"
        }
      }
    }

    dnat_rules = Hash[find_nat_rules(@location).map do |rule|
      [
        "#{rule.from.host} #{rule.from.port}",
        {
          'dest_host' => "#{rule.to.host}",
          'dest_port' => "#{rule.to.port}",
          'tcp'       => "#{rule.tcp}",
          'udp'       => "#{rule.udp}"
        }
      ]
    end]

    dnat = {
      'DNAT' => dnat_rules
    }
    rules.merge! snat
    rules.merge! dnat

    enc.merge('role::natserver' => {
                'rules' => rules,
                'front_virtual_router_id' => virtual_router_ids[:front],
                'prod_virtual_router_id' => virtual_router_ids[:prod]
              })
  end
end
