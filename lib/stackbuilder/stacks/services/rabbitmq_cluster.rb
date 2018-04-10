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
    @supported_requirements = :accept_any_requirement_default_all_servers
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
    realservers = cluster_nodes(location)
    return {} if realservers.size == 0
    {
      vip_fqdn(:prod, fabric) => {
        'type' => 'rabbitmq',
        'ports' => @ports,
        'realservers' => {
          'blue' => realservers
        }
      }
    }
  end

  def validate_dependency(dependant, dependency)
    fail "Stack '#{dependant.name}' must specify requirement when using depend_on #{name} "\
          "in environment '#{environment.name}'. Usage: depend_on <environment>, <requirement>" \
          if dependency[2].nil?
  end

  def requirements_of(dependant)
    dependent_on_this_cluster = dependant.depends_on.select { |dependency| dependency[0] == name && dependency[1] == environment.name }
    dependent_on_this_cluster.inject([]) do |requirements, dependency|
      validate_dependency(dependant, dependency)
      requirements << dependency[2]
    end
  end

  def config_params(dependent, _fabric, _dependent_instance)
    acceptable_supported_requirements = [:accept_any_requirement_default_all_servers]
    fail "Stack '#{name}' invalid supported requirements: #{supported_requirements} "\
          "in environment '#{environment.name}'. Acceptable supported requirements: "\
          "#{acceptable_supported_requirements}." \
          unless acceptable_supported_requirements.include?(@supported_requirements)

    config_properties(dependent, children.map(&:prod_fqdn))
  end

  def config_properties(dependent, fqdns)
    requirements = requirements_of(dependent)
    config_params = {}
    requirements.each do |requirement|
      config_params.merge!(
        "#{requirement}.messaging.enabled" => 'true',
        "#{requirement}.messaging.broker_fqdns" => fqdns.sort.join(','),
        "#{requirement}.messaging.username" => "#{dependent.application}",
        "#{requirement}.messaging.password_hiera_key" =>
          "#{dependent.environment.name}/#{dependent.application}/messaging_password"
      )
    end
    config_params
  end

  def dependant_users
    users = {}
    virtual_services_that_depend_on_me.each do |service|
      next unless service.is_a?(Stacks::Services::RabbitMqDependent)
      rabbitmq_config = service.rabbitmq_config
      users.merge!(
        rabbitmq_config.username => {
          'tags'               => [],
          'password_hiera_key' => rabbitmq_config.password_hiera_key
        }
      )
    end
    users
  end
end
