require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def_container'
require 'uri'

module Stacks::Services::ExternalServerCluster
  def configure
    @instances = 1
  end

  def self.extended(object)
    object.configure
  end
end
