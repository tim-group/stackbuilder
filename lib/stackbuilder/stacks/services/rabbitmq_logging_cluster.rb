require 'stackbuilder/stacks/namespace'

module Stacks::Services::RabbitMqLoggingCluster
  include Stacks::Services::RabbitMqDependent

  HardcodedUser = Struct.new(:rabbitmq_config, :prod_fqdn)

  def self.extended(object)
    object.configure
  end

  attr_accessor :instances
  attr_accessor :harcoded_users

  def configure
    @instances = 2
    @hardcoded_users = []
  end

  def rabbitmq_config
    create_rabbitmq_config('shovel')
  end

  def add_rabbitmq_user(username, password_hiera_key, prod_fqdn)
    @hardcoded_users << HardcodedUser.new(RabbitMq.new(username, password_hiera_key), prod_fqdn)
  end

  def cluster_nodes
    @definitions.values.map(&:prod_fqdn).sort.map { |fqdn| fqdn.split('.')[0] }
  end

  def dependent_instances(location)
    (dependant_instance_fqdns(location) + @hardcoded_users.map(&:prod_fqdn))
  end

  def dependant_users
    users = {}
    virtual_services_that_i_depend_on.each do |service|
      next unless service.is_a?(Stacks::Services::RabbitMqDependent)
      rabbitmq_config = self.rabbitmq_config
      users.merge!(
        rabbitmq_config.username => {
          'tags'               => [],
          'password_hiera_key' => rabbitmq_config.password_hiera_key
        }
      )
    end

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

    hardcoded_users_in_enc_format = @hardcoded_users.inject({}) do |hardcoded_users_map, hardcoded_user|
      hardcoded_users_map[hardcoded_user.rabbitmq_config.username] = {
        'tags' => [],
        'password_hiera_key' => hardcoded_user.rabbitmq_config.password_hiera_key }
      hardcoded_users_map
    end

    users.merge(hardcoded_users_in_enc_format)
  end

  def shovel_destinations
    virtual_services_that_i_depend_on.select do |service|
      service.is_a?(Stacks::Services::RabbitMqLoggingCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end
end
