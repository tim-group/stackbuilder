require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/virtual_service'
require 'stacks/virtual_proxy_service'
require 'stacks/virtual_app_service'
require 'stacks/loadbalancer'
require 'stacks/nat_server'
require 'stacks/proxy_server'
require 'stacks/virtual_sftp_service'
require 'stacks/virtual_rabbitmq_service'
require 'stacks/ci_slave'
require 'stacks/puppetmaster'

class Stacks::Stack
  attr_reader :name

  include Stacks::MachineDefContainer

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def virtual_appserver(name, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend(Stacks::VirtualService)
    machineset.extend(Stacks::AppService)
    machineset.type=Stacks::AppServer
    @definitions[name] = machineset
  end

  def virtual_proxyserver(name, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend(Stacks::VirtualService)
    machineset.extend(Stacks::XProxyService)
    machineset.type=Stacks::ProxyServer
    @definitions[name] = machineset
  end

  def virtual_sftpserver(name, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend(Stacks::VirtualService)
    machineset.extend(Stacks::VirtualSftpService)
    machineset.type=Stacks::SftpServer
    @definitions[name] = machineset
  end

  def virtual_rabbitmqserver(&block)
    machineset = Stacks::MachineSet.new("rabbitmq", &block)
    machineset.extend(Stacks::VirtualService)
    machineset.extend(Stacks::VirtualRabbitMQService)
    machineset.type=Stacks::RabbitMQServer
    @definitions[name] = machineset
  end

  def puppetmaster(name="puppetmaster-001")
    @definitions[name] = Stacks::PuppetMaster.new(name)
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

  def ci_slave(options={:instances=>1})
    options[:instances].times do |i|
      index = sprintf("%03d",i+1)
      hostname = "jenkinsslave-#{index}"
      @definitions[hostname] = Stacks::CiSlave.new(hostname)
    end
  end

  def [](key)
    return @definitions[key]
  end

end
