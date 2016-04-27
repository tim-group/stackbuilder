require 'stackbuilder/stacks/namespace'

module Stacks::Services::RabbitMQCluster
  def self.extended(object)
    object.configure
  end

  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup
  attr_accessor :supported_requirements

  def configure
    @downstream_services = []
    @ports = [5672]
    # FIXME: Remove this when all rabbitmq's are specified with requirement
    @supported_requirements = :default
  end

  def clazz
    'rabbitmqcluster'
  end

  def cluster_nodes(location)
    realservers(location).map(&:prod_fqdn).sort.map do |fqdn|
      fqdn.split('.')[0]
    end
  end

  def to_loadbalancer_config(location, fabric)
    {
      vip_fqdn(:prod, fabric) => {
        'type' => 'rabbitmq',
        'ports' => @ports,
        'realservers' => {
          'blue' => cluster_nodes(location)
        }
      }
    }
  end

  def requirement_of(dependant)
    dependent_on_this_cluster = dependant.depends_on.find { |dependency| dependency[0] == name }
    return dependent_on_this_cluster[2] unless dependent_on_this_cluster[2].nil?
  end

  def config_params(dependent, _fabric)
    # FIXME: Remove :default when all rabbitmq's are specified with requirement
    acceptable_supported_requirements = [:accept_any_requirement_default_all_servers, :default]
    fail "'Stack '#{name}' invalid supported requirements: #{supported_requirements} "\
          "in environment '#{environment.name}'. Acceptable supported requirements: "\
          "#{acceptable_supported_requirements}." \
          unless acceptable_supported_requirements.include?(@supported_requirements)

    config_properties(dependent, children.map(&:prod_fqdn))
  end

  def config_properties(dependent, fqdns)
    requirement = requirement_of(dependent)
    # FIXME: Remove when all rabbitmq's are specified with requirement
    return {} if requirement.nil?
    config_params = {
      "#{requirement}.messaging.enabled" => 'true',
      "#{requirement}.messaging.broker_fqdns" => fqdns.sort.join(','),
      "#{requirement}.messaging.username" => dependent.application,
      "#{requirement}.messaging.password_hiera_key" =>
        "enc/#{dependent.environment.name}/#{dependent.application}/messaging_#{requirement}_password"
    }
    config_params
  end
end
