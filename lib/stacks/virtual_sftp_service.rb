require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/sftp_server'
require 'stacks/nat'
require 'uri'

class Stacks::VirtualSftpService < Stacks::VirtualService
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def initialize(name, &config_block)
    super(name, &config_block)
    @downstream_services = []
    @config_block = config_block
    @ports = [22]
  end

  def bind_to(environment)
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = Stacks::SftpServer.new(self, index, &@config_block)
    end
    super(environment)
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
