require 'stacks/namespace'

class Stacks::NatServer < Stacks::MachineDef

  def initialize(base_hostname)
    super(base_hostname, [:mgmt, :prod, :front])
  end

  def bind_to(environment)
    super(environment)
  end

  def find_nat_rules
    rules = []
    environment.accept do |node|

      unless node.environment.contains_node_of_type?(Stacks::NatServer) && environment != node.environment
        if node.respond_to? :nat
          rules << node.nat_rule if node.nat
        end
      end
    end
    rules
  end

  def to_enc
    rules = {}

    snat = {
      'SNAT' => {
        'prod' => {
          'to_source' => "nat-vip.front.#{environment.options[:primary]}.net.local"
        }
      }
    }

    dnat_rules = Hash[find_nat_rules.map do |rule|
      [
        "#{rule.from.host} #{rule.from.port}",
        {
          'dest_host' => "#{rule.to.host}",
          'dest_port' => "#{rule.to.port}"
        }
      ]
    end]

    dnat = {
      'DNAT' => dnat_rules
    }
    rules.merge! snat
    rules.merge! dnat

    {
      'role::natserver' => {
        'rules' => rules
      }
    }
  end
end
