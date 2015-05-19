require 'stacks/services/namespace'
require 'stacks/gold'
require 'stacks/namespace'

class Stacks::CustomServices
  attr_reader :name

  include Stacks::MachineDefContainer

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def virtual_appserver(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::AppService],
                    Stacks::Services::AppServer, &block)
  end

  def standalone_appserver(name, &block)
    machineset_with(name, [Stacks::Services::AppService], Stacks::Services::AppServer, &block)
  end

  def virtual_proxyserver(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualProxyService],
                    Stacks::Services::ProxyServer, &block)
  end

  def virtual_sftpserver(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualSftpService],
                    Stacks::Services::SftpServer, &block)
  end

  def virtual_rabbitmqserver(name = 'rabbitmq', &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualRabbitMQService],
                    Stacks::Services::RabbitMQServer, &block)
  end

  def virtual_bindserver(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualBindService],
                    Stacks::Services::BindServer, &block)
  end

  def virtual_mailserver(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualMailService],
                    Stacks::Services::MailServer, &block)
  end

  def shadow_server(name, &block)
    machineset_with(name, [Stacks::Services::ShadowServerCluster], Stacks::Services::ShadowServer, &block)
  end

  def mongodb(name = 'mongodb', &block)
    machineset_with(name, [Stacks::Services::MongoDBCluster], Stacks::Services::MongoDBServer, &block)
  end

  def mysql_cluster(name = 'mysqldb', &block)
    machineset_with(name, [Stacks::Services::MysqlCluster], Stacks::Services::MysqlServer, &block)
  end

  def legacy_mysqldb(name = 'mysqldb', &block)
    machineset_with(name, [Stacks::Services::LegacyMysqlCluster], Stacks::Services::LegacyMysqlDBServer, &block)
  end

  def logstash(name = 'logstash', &block)
    machineset_with(name, [], Stacks::Services::LogstashServer, &block)
  end

  def fmanalyticsanalysis(name = 'fmanalyticsanalysis', &block)
    machineset_with(name, [], Stacks::Services::FmAnalyticsAnalysisServer, &block)
  end

  def fmanalyticsreporting(name = 'fmanalyticsreporting', &block)
    machineset_with(name, [], Stacks::Services::FmAnalyticsReportingServer, &block)
  end

  def puppetmaster(name = "puppetmaster", &block)
    machineset_with(name, [], Stacks::Services::PuppetMaster, &block)
  end

  def loadbalancer(&block)
    machineset_with('lb', [Stacks::Services::LoadBalancerCluster], Stacks::Services::LoadBalancer, &block)
  end

  def natserver(&block)
    machineset_with('nat', [], Stacks::Services::NatServer, &block)
  end

  def elasticsearch(name = 'elasticsearch', &block)
    machineset_with(name, [], Stacks::Services::ElasticSearchNode, &block)
  end

  def rate_limited_forward_proxy(name = 'rate_limited_forward_proxy', &block)
    machineset_with(name, [], Stacks::Services::RateLimitedForwardProxyServer, &block)
  end

  def selenium_hub(name = 'hub-001', options = {})
    @definitions[name] = Stacks::Services::Selenium::Hub.new(name, @definitions, options)
  end

  def selenium_node_cluster(name = 'segrid', &block)
    machineset_with(name, [Stacks::Services::Selenium::Cluster], nil, &block)
  end

  def gold(name, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend Stacks::Gold
    @definitions[name] = machineset
  end

  def debrepo(name, &block)
    machineset_with(name, [], Stacks::Services::DebRepo, &block)
  end

  def debrepo_mirror(name, &block)
    machineset_with(name, [], Stacks::Services::DebRepoMirror, &block)
  end

  def cislave(name, &block)
    machineset_with(name, [], Stacks::Services::CiSlave, &block)
  end

  def eventstore(name = 'eventstore', &block)
    machineset_with(name, [Stacks::Services::EventStoreCluster], Stacks::Services::EventStoreServer, &block)
  end

  def pentaho_server(name = 'pentaho_server', &block)
    machineset_with(name, [Stacks::Services::AppService], Stacks::Services::PentahoServer, &block)
  end

  def quantapp(name = 'quantapp', &block)
    machineset_with(name, [], Stacks::Services::QuantAppServer, &block)
  end

  def sensu(name = 'sensu', &block)
    machineset_with(name, [], Stacks::Services::SensuServer, &block)
  end

  def shiny(name = 'shiny', &block)
    machineset_with(name, [], Stacks::Services::ShinyServer, &block)
  end

  def standard(name, &block)
    machineset_with(name, [], Stacks::Services::StandardServer, &block)
  end

  def [](key)
    @definitions[key]
  end

  private

  def machineset_with(name, extends, type, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend(Stacks::MachineGroup)
    machineset.extend(Stacks::Dependencies)
    extends.each { |e| machineset.extend(e) }
    machineset.type = type
    @definitions[name] = machineset
  end
end
