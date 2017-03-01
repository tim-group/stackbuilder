require 'stackbuilder/stacks/namespace'

module Stacks::Services::RabbitMqLoggingCluster
  def self.extended(object)
    object.configure
  end

  def configure
  end
end
