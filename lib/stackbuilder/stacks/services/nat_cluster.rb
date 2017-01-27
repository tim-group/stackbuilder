require 'stackbuilder/stacks/namespace'

module Stacks::Services::NatCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def snat_rules
    rules = {}
    find_rules_for(:snat).each do |rule|
      rules["#{rule.from.host} #{rule.from.port}"] = {
        'to_source' => "#{rule.to.host}:#{rule.to.port}",
        'tcp'       => rule.tcp,
        'udp'       => rule.udp
      }
    end
    rules['prod'] = {
      'to_source' => "nat-vip.front.#{environment.options[:primary_site]}.net.local"
    }
    rules
  end

  def dnat_rules
    Hash[find_rules_for(:dnat).map do |rule|
      [
        "#{rule.from.host} #{rule.from.port}",
        {
          'dest_host' => "#{rule.to.host}",
          'dest_port' => "#{rule.to.port}",
          'tcp'       => rule.tcp,
          'udp'       => rule.udp
        }
      ]
    end]
  end

  def clazz
    'natcluster'
  end

  private

  def find_rules_for(nat_rule_type)
    nat_site = environment.primary_site

    virtual_services_that_depend_on_me.select do |dependency|
      dependency.environment.sites.include? nat_site
    end.map do |dependency_in_nat_site|
      dependency_in_nat_site.calculate_nat_rules(nat_rule_type, nat_site)
    end.flatten
  end
end
