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
end
