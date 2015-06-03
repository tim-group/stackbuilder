require 'stackbuilder/stacks/namespace'

module Stacks::Services::NatCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def snat_rules
    {
      'prod' => {
        'to_source' => "nat-vip.front.#{environment.options[:primary_site]}.net.local"
      }
    }
  end

  def dnat_rules
    Hash[find_nat_rules.map do |rule|
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

  def clazz
    'natcluster'
  end

  private

  def find_services_that_require_nat
    virtual_services.select do |node|
      node.respond_to?(:nat) &&
        node.nat == true
    end
  end

  def environment_services_that_require_nat
    find_services_that_require_nat.select do |node|
      node.environment == environment
    end
  end

  def sub_environment_services_that_require_nat
    find_services_that_require_nat.select do |node|
      node.environment.parent == environment &&
        !node.environment.contains_node_of_type?(Stacks::Services::NatServer)
    end
  end

  def secondary_site_services_that_require_nat
    find_services_that_require_nat.select do |node|
      node.environment != environment &&
        node.respond_to?(:secondary_site?) &&
        node.secondary_site? == true &&
        node.environment.secondary_site == environment.primary_site
    end
  end

  def find_nat_rules
    rules = []
    services = environment_services_that_require_nat
    services = services.concat(sub_environment_services_that_require_nat)
    services.each do |service|
      rules = rules.concat(service.nat_rules(:primary_site))
    end
    secondary_site_services_that_require_nat.uniq.each do |service|
      rules = rules.concat(service.nat_rules(:secondary_site))
    end
    rules
  end
end
