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
      if node.respond_to? :nat
        rules << node.nat_rule if node.nat
      end
    end
    rules
  end

  def to_enc
    rules = find_nat_rules.map do |rule|
      {
        'to' => rule.to,
        'from' => rule.from
      }
    end

    {
      'role::natserver' => {
        'rules' => rules
      }
    }
  end
end
