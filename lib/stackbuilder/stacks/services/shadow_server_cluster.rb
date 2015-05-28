require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'uri'

module Stacks::Services::ShadowServerCluster
  def configure
    @instances = 1
  end

  def self.extended(object)
    object.configure
  end
end
