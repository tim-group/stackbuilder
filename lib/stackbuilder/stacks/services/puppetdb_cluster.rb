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

  def instantiate_machine(i, _environment, _network, location)
    index = sprintf("%03d", i + 1)
    @type.new(self, index, location)
  end
end
