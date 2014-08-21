require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/virtual_service'
require 'stacks/virtual_proxy_service'
require 'stacks/machine_set'
require 'stacks/app_service'
require 'stacks/loadbalancer'
require 'stacks/nat_server'
require 'stacks/proxy_server'
require 'stacks/virtual_sftp_service'
require 'stacks/virtual_rabbitmq_service'
require 'stacks/ci_slave'
require 'stacks/deb_repo'
require 'stacks/deb_repo_mirror'
require 'stacks/elasticsearch_node'
require 'stacks/rate_limited_forward_proxy_server'
require 'stacks/puppetmaster'
require 'stacks/selenium/hub'
require 'stacks/mongodb_server'
require 'stacks/mysqldb_server'
require 'stacks/mysql_cluster'
require 'stacks/quantapp_server'
require 'stacks/standard_server'
require 'stacks/logstash_server'
require 'stacks/fmanalyticsapp_server'
require 'stacks/analyticsapp_server'

class Stacks::Stack
  attr_reader :name

  include Stacks::MachineDefContainer

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def virtual_appserver(name, &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::AppService], Stacks::AppServer, &block);
  end

  def standalone_appserver(name, &block)
    machineset_with(name, [Stacks::AppService], Stacks::AppServer, &block);
  end

  def virtual_proxyserver(name, &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::XProxyService], Stacks::ProxyServer, &block)
  end

  def virtual_sftpserver(name, &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::VirtualSftpService], Stacks::SftpServer, &block)
  end

  def virtual_rabbitmqserver(&block)
    machineset_with('rabbitmq', [Stacks::VirtualService, Stacks::VirtualRabbitMQService], Stacks::RabbitMQServer, &block)
  end

  def mongodb(name='mongodb', &block)
    machineset_with(name, [], Stacks::MongoDBServer, &block)
  end

  def mysqldb(name='mysqldb', &block)
    machineset_with(name, [Stacks::MysqlCluster], Stacks::MysqlDBServer, &block)
  end

  def logstash(name='logstash', &block)
    machineset_with(name, [], Stacks::LogstashServer, &block)
  end

  def analyticsapp(name='analyticsapp', &block)
    machineset_with(name, [], Stacks::AnalyticsAppServer, &block)
  end

  def fmanalyticsapp(name='fmanalyticsapp', &block)
    machineset_with(name, [], Stacks::FmAnalyticsAppServer, &block)
  end

  def puppetmaster(name="puppetmaster", &block)
    machineset_with(name, [], Stacks::PuppetMaster, &block)
  end

  def loadbalancer(&block)
    machineset_with('lb', [], Stacks::LoadBalancer, &block)
  end

  def natserver(&block)
    machineset_with('nat', [], Stacks::NatServer, &block)
  end

  def elasticsearch(name = 'elasticsearch', &block)
    machineset_with(name, [], Stacks::ElasticSearchNode, &block)
  end

  def rate_limited_forward_proxy(name='rate_limited_forward_proxy', &block)
    machineset_with(name, [], Stacks::RateLimitedForwardProxyServer, &block)
  end

  def segrid(name='segrid', options={}, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend Stacks::Selenium::Grid
    @definitions[name] = machineset
  end

  def debrepo(name, &block)
    machineset_with(name, [], Stacks::DebRepo, &block)
  end
  def debrepo_mirror(name, &block)
    machineset_with(name, [], Stacks::DebRepoMirror, &block)
  end

  def cislave(name, &block)
    machineset_with(name, [], Stacks::CiSlave, &block)
  end

  def quantapp(name='quantapp', &block)
    machineset_with(name, [], Stacks::QuantAppServer, &block)
  end

  def standard(name, &block)
    machineset_with(name, [], Stacks::StandardServer, &block)
  end

  def [](key)
    return @definitions[key]
  end

  private
  def machineset_with(name, extends, type, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend(Stacks::MachineGroup)
    extends.each { |e| machineset.extend(e) }
    machineset.type=type
    @definitions[name]=machineset
  end
end

