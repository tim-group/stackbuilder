require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/sftp_server'
require 'stacks/nat'
require 'uri'

module Stacks::VirtualSftpService
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def self.extended(object)
    object.configure
  end

  def configure
    @downstream_services = []
    @ports = [21, 22, 2222]
  end

  def ssh_dependant_instances_fqdns(networks = [:mgmt])
    virtual_service_children = get_children_for_virtual_services(virtual_services_that_depend_on_me)
    virtual_service_children.reject! { |machine_def| machine_def.class != Stacks::AppServer }
    machine_defs_to_fqdns(virtual_service_children, networks)
  end

  def to_loadbalancer_config
    grouped_realservers = realservers.group_by do |realserver|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, realservers|
      realserver_fqdns = realservers.map(&:prod_fqdn).sort
      [group, realserver_fqdns]
    end]

    {
      vip_fqdn(:prod) => {
        'type'         => 'sftp',
        'ports'        => @ports,
        'realservers'  => realservers,
        'persistent_ports'  => @persistent_ports
      }
    }
  end
end
