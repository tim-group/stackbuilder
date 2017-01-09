require 'stackbuilder/stacks/namespace'

module Stacks::Services::PuppetdbCluster
  include Stacks::Services::AppService

  def self.extended(object)
    object.configure
  end

  attr_accessor :cluster_name
  attr_accessor :version

  def configure
    @cluster_name = @name
    @instances = 1
    @version = '2.3.8-1puppetlabs1'
  end
end
