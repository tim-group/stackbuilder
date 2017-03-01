require 'stackbuilder/stacks/namespace'

module Stacks::Services::RabbitMqLoggingCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :instances

  def configure
    @instances = 2
  end

  def cluster_nodes
    @definitions.values.map(&:prod_fqdn).sort.map { |fqdn| fqdn.split('.')[0] }
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
