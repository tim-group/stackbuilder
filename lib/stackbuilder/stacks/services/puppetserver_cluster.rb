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
    machine_defs_i_depend_on.reject do |machine_def|
      machine_def.class != Stacks::Services::Puppetdb
    end.first.qualified_hostname(:mgmt)
  end

  def instantiate_machine(i, environment, _network, location)
    index = sprintf("%03d", i + 1)
    server = @type.new(self, index, location)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    server
  end
end
