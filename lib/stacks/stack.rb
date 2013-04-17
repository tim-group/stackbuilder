require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/virtual_service'
require 'stacks/virtual_proxy_service'
require 'stacks/virtual_app_service'
require 'stacks/loadbalancer'
require 'stacks/nat_server'
require 'stacks/proxy_server'
require 'stacks/virtual_sftp_service'

class Stacks::Stack
  attr_reader :name

  include Stacks::MachineDefContainer

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def virtual_appserver(name, &block)
    @definitions[name] = virtualservice = Stacks::VirtualAppService.new(name, &block)
    virtualservice.instance_eval(&block) unless block.nil?
  end

  def virtual_proxyserver(name, &block)
    @definitions[name] = virtualservice = Stacks::VirtualProxyService.new(name, &block)
    #virtualservice.instance_eval(&block) unless block.nil?
  end

  def virtual_sftpserver(name, &block)
    @definitions[name] = virtualservice = Stacks::VirtualSftpService.new(name, &block)
  end

  def loadbalancer(options={:instances=>2})
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      hostname = "lb-#{index}"
      @definitions[hostname] = Stacks::LoadBalancer.new(hostname)
    end
  end

  def natserver(options={:instances=>2})
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      hostname = "nat-#{index}"
      @definitions[hostname] = Stacks::NatServer.new(hostname)
    end
  end

  def [](key)
    return @definitions[key]
  end

end
