require 'stackbuilder/stacks/namespace'

module Stacks::Services::PuppetdbCluster
  include Stacks::Services::AppService

  def self.extended(object)
    object.configure
  end

  attr_accessor :cluster_name

  def configure
    @cluster_name = @name
    @instances = 1
  end

  def instantiate_machine(i, environment, _network, location)
    index = sprintf("%03d", i + 1)
    server = @type.new(self, index, location)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    server
  end
end
