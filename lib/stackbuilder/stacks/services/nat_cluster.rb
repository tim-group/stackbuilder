require 'stackbuilder/stacks/namespace'

module Stacks::Services::NatCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end

  def snat_rules
    rules = {}
    find_snat_rules.each do |rule|
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
    Hash[find_dnat_rules.map do |rule|
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

  def find_dnat_rules
    rules = []
    virtual_services_that_depend_on_me.each do |dependency|
      if dependency.environment.primary_site == environment.primary_site
        rules = rules.concat(dependency.dnat_rules_for_dependency(:primary_site, requirements_of(dependency)))
      end
      if dependency.secondary_site? && dependency.environment.secondary_site == environment.primary_site
        rules = rules.concat(dependency.dnat_rules_for_dependency(:secondary_site, requirements_of(dependency)))
      end
    end

    rules
  end

  def find_snat_rules
    rules = []
    virtual_services_that_depend_on_me.each do |dependency|
      if dependency.environment.primary_site == environment.primary_site
        rules = rules.concat(dependency.snat_rules_for_dependency(:primary_site, requirements_of(dependency)))
      end
      if dependency.secondary_site? && dependency.environment.secondary_site == environment.primary_site
        rules = rules.concat(dependency.snat_rules_for_dependency(:secondary_site, requirements_of(dependency)))
      end
    end
    rules
  end
end
