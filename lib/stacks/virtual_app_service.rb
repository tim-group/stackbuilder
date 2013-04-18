require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

class Stacks::VirtualAppService < Stacks::VirtualService
  attr_accessor :application
  attr_accessor :groups
  attr_accessor :ram

  def initialize(name, &config_block)
    @groups = ['blue']
    super(name, &config_block)
    @ports = [@port]
  end

  def bind_to(environment)
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = Stacks::AppServer.new(self, index, &@config_block)
      server.group = groups[i%groups.size]
      server.ram   = @ram unless @ram.nil?
    end
    super(environment)
    self.instance_eval(&@config_block) unless @config_block.nil?
  end

  def to_loadbalancer_config
    grouped_realservers = self.realservers.group_by do |realserver|
      realserver.group
    end

    realservers = Hash[grouped_realservers.map do |group, realservers|
      realserver_fqdns = realservers.map do |realserver|
        realserver.prod_fqdn
      end.sort
      [group, realserver_fqdns]
    end]

    [self.vip_fqdn, {
      'env' => self.environment.name,
      'app' => self.application,
      'realservers' => realservers
    }]

  end
end
