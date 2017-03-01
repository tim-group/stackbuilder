require 'stackbuilder/stacks/namespace'

module Stacks::Services::RabbitMqLoggingCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :instances

  def configure
    @instances = 2
  end
end
