require 'stackbuilder/stacks/namespace'

module Stacks::Services::PuppetserverCluster
  include Stacks::Services::AppService

  def self.extended(object)
    object.configure
  end

  attr_accessor :cluster_name

  def configure
    @cluster_name = @name
    @instances = 1
  end

  def puppetdb_that_i_depend_on
    machine_defs_i_depend_on = get_children_for_virtual_services(virtual_services_that_i_depend_on)
    puppetdbs = machine_defs_i_depend_on.reject do |machine_def|
      machine_def.class != Stacks::Services::Puppetdb
    end
    return if puppetdbs.empty?
    puppetdbs.sort { |a, b| a.name <=> b.name }.first.qualified_hostname(:mgmt)
  end
end
