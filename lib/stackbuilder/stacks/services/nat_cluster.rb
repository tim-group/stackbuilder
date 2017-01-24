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

  def find_dependencies_that_require_dnat
    virtual_services_that_depend_on_me
  end

  def find_services_that_require_dnat
    @environment.virtual_services.select do |node|
      node.respond_to?(:nat) &&
        node.nat == true
    end
  end

  def find_services_that_require_snat
    @environment.virtual_services.select do |node|
      node.respond_to?(:nat_out) &&
        node.nat_out == true
    end
  end

  def environment_services_that_require_dnat
    find_services_that_require_dnat.select do |node|
      node.environment == environment
    end
  end

  def environment_services_that_require_snat
    find_services_that_require_snat.select do |node|
      node.environment == environment
    end
  end

  def sub_environment_services_that_require_dnat
    find_services_that_require_dnat.select do |node|
      node.environment.parent == environment &&
        !node.environment.contains_node_of_type?(Stacks::Services::NatServer)
    end
  end

  def sub_environment_services_that_require_snat
    find_services_that_require_snat.select do |node|
      node.environment.parent == environment &&
        !node.environment.contains_node_of_type?(Stacks::Services::NatServer)
    end
  end

  def secondary_site_services_that_require_dnat
    find_services_that_require_dnat.select do |node|
      node.environment != environment &&
        node.respond_to?(:secondary_site?) &&
        node.secondary_site? == true &&
        node.environment.secondary_site == environment.primary_site
    end
  end

  def secondary_site_services_that_require_snat
    find_services_that_require_snat.select do |node|
      node.environment != environment &&
        node.respond_to?(:secondary_site?) &&
        node.secondary_site? == true &&
        node.environment.secondary_site == environment.primary_site
    end
  end

  def find_dnat_rules
    rules = []
    services = environment_services_that_require_dnat
    services = services.concat(sub_environment_services_that_require_dnat)
    services.each do |service|
      rules = rules.concat(service.dnat_rules(:primary_site))
    end
    secondary_site_services_that_require_dnat.uniq.each do |service|
      rules = rules.concat(service.dnat_rules(:secondary_site))
    end

    find_dependencies_that_require_dnat.each do |dependency|
      rules = rules.concat(dependency.dnat_rules(:primary_site))
    end
    rules
  end

  def find_snat_rules
    rules = []
    services = environment_services_that_require_snat
    services = services.concat(sub_environment_services_that_require_snat)
    services.each do |service|
      rules = rules.concat(service.snat_rules(:primary_site))
    end
    secondary_site_services_that_require_snat.uniq.each do |service|
      rules = rules.concat(service.snat_rules(:secondary_site))
    end
    rules
  end
end
