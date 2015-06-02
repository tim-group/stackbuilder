require 'stackbuilder/stacks/namespace'

module Stacks::Services::NatCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def snat_rules(location)
    {
      'prod' => {
        'to_source' => "nat-vip.front.#{environment.options[location]}.net.local"
      }
    }
  end

  def dnat_rules(location)
    Hash[find_nat_rules(location).map do |rule|
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

  def clazz
    'natcluster'
  end
end
