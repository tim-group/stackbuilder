require 'stacks/namespace'

class Stacks::NatServer < Stacks::MachineDef
  attr_reader :virtual_router_ids

  def initialize(server_group, index, &block)
    super(server_group.name + "-" + index, [:mgmt, :prod, :front])
    @virtual_router_ids = {}
    self
  end

  def bind_to(environment)
    super(environment)
    @virtual_router_ids[:front] = environment.options[:nat_front_virtual_router_id] || 105
    @virtual_router_ids[:prod] = environment.options[:nat_prod_virtual_router_id] || 106
  end

  def find_nat_rules
    rules = []
    environment.accept do |node|
      if (node.environment == nil)
        puts node.name
      end
      unless node.environment.contains_node_of_type?(Stacks::NatServer) && environment != node.environment
        if node.respond_to? :nat
          rules =  rules.concat node.nat_rules if node.nat
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
          'to_source' => "nat-vip.front.#{environment.options[:primary_site]}.net.local"
        }
      }
    }

    dnat_rules = Hash[find_nat_rules.map do |rule|
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

    enc.merge({
                'role::natserver' => {
                  'rules' => rules,
                  'front_virtual_router_id' => virtual_router_ids[:front],
                  'prod_virtual_router_id' => virtual_router_ids[:prod]
                }
              })
  end
end
