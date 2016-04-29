require 'stackbuilder/stacks/namespace'

module Stacks::Services::RabbitMQCluster
  def self.extended(object)
    object.configure
  end

  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup
  attr_accessor :supported_requirements
  ### FIXME: rpearce 29/04/2016 remove when applications can accept new config
  attr_accessor :temporary_workaround_to_broken_merc_config

  def configure
    @downstream_services = []
    @ports = [5672]
    @supported_requirements = :accept_any_requirement_default_all_servers

    ### FIXME: rpearce 29/04/2016 remove when applications can accept new config
    @temporary_workaround_to_broken_merc_config = true
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
    fail "Stack '#{dependant.name}' must specify requirement when using depend_on #{name} "\
          "in environment '#{environment.name}'. Usage: depend_on <environment>, <requirement>" \
          if dependent_on_this_cluster[2].nil?
    dependent_on_this_cluster[2]
  end

  def config_params(dependent, _fabric)
    acceptable_supported_requirements = [:accept_any_requirement_default_all_servers]
    fail "Stack '#{name}' invalid supported requirements: #{supported_requirements} "\
          "in environment '#{environment.name}'. Acceptable supported requirements: "\
          "#{acceptable_supported_requirements}." \
          unless acceptable_supported_requirements.include?(@supported_requirements)

    config_properties(dependent, children.map(&:prod_fqdn))
  end

  def config_properties(dependent, fqdns)
    requirement = requirement_of(dependent)
    ### FIXME: rpearce 29/04/2016 remove when applications can accept new config
    return {} if @temporary_workaround_to_broken_merc_config
    config_params = {
      "#{requirement}.messaging.enabled" => 'true',
      "#{requirement}.messaging.broker_fqdns" => fqdns.sort.join(','),
      "#{requirement}.messaging.username" => dependent.application,
      "#{requirement}.messaging.password_hiera_key" =>
        "enc/#{dependent.environment.name}/#{dependent.application}/messaging_#{requirement}_password"
    }
    config_params
  end

  def dependant_users
    users = {}
    virtual_services_that_depend_on_me.each do |service|
      next unless service.respond_to?(:application)
      requirement = requirement_of(service)
      users.merge!(
        service.application => {
          'password_hiera_key' =>
            "enc/#{service.environment.name}/#{service.application}/messaging_#{requirement}_password",
          'tags' => []
        }
      )
    end
    { 'dependant_users' => users }
  end
end
