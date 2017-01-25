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
    nat_site = environment.primary_site
    virtual_services_that_depend_on_me.each do |dependency|
      dependency_sites = dependency.environment.sites
      dependency_sites.each do |site|
        if site == nat_site
          rules = rules.concat(dependency.dnat_rules_for_dependency(site, requirements_of(dependency)))
        end
      end
    end
    rules
  end

  def find_snat_rules
    rules = []
    nat_site = environment.primary_site

    virtual_services_that_depend_on_me.each do |dependency|
      dependency_sites = dependency.environment.sites
      dependency_sites.each do |site|
        if site == nat_site
          rules = rules.concat(dependency.snat_rules_for_dependency(site, requirements_of(dependency)))
        end
      end
    end
    rules
  end
end
