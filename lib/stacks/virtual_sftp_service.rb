require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/sftp_server'
require 'stacks/nat'
require 'uri'

module Stacks::VirtualSftpService
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def self.extended(object)
    object.configure()
  end

  def configure()
    @downstream_services = []
    @ports = [22]
  end

  def to_loadbalancer_config
    grouped_realservers = self.realservers.group_by do |realserver|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, realservers|
      realserver_fqdns = realservers.map do |realserver|
        realserver.prod_fqdn
      end.sort
      [group, realserver_fqdns]
    end]

    [self.vip_fqdn, {
      'type' => 'sftp',
      'realservers' => realservers
    }]
  end
end
