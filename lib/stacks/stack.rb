require 'stacks/namespace'
require 'stacks/app_service'
require 'stacks/bind_server'
require 'stacks/ci_slave'
require 'stacks/deb_repo'
require 'stacks/deb_repo_mirror'
require 'stacks/elasticsearch_node'
require 'stacks/fmanalyticsanalysis_server'
require 'stacks/fmanalyticsreporting_server'
require 'stacks/gold'
require 'stacks/legacy_mysql_cluster'
require 'stacks/legacy_mysqldb_server'
require 'stacks/loadbalancer'
require 'stacks/loadbalancer_cluster'
require 'stacks/logstash_server'
require 'stacks/machine_def_container'
require 'stacks/machine_group'
require 'stacks/machine_set'
require 'stacks/mail_server'
require 'stacks/mongodb_cluster'
require 'stacks/mongodb_server'
require 'stacks/mysql_cluster'
require 'stacks/mysql_server'
require 'stacks/nat_server'
require 'stacks/pentaho'
require 'stacks/proxy_server'
require 'stacks/puppetmaster'
require 'stacks/quantapp_server'
require 'stacks/rate_limited_forward_proxy_server'
require 'stacks/selenium/cluster'
require 'stacks/selenium/hub'
require 'stacks/sensu_server'
require 'stacks/shadow_server'
require 'stacks/shadow_server_cluster'
require 'stacks/standard_server'
require 'stacks/virtual_bind_service'
require 'stacks/virtual_mail_service'
require 'stacks/virtual_proxy_service'
require 'stacks/virtual_rabbitmq_service'
require 'stacks/virtual_service'
require 'stacks/virtual_sftp_service'

class Stacks::Stack
  attr_reader :name

  include Stacks::MachineDefContainer

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def virtual_appserver(name, &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::AppService], Stacks::AppServer, &block)
  end

  def standalone_appserver(name, &block)
    machineset_with(name, [Stacks::AppService], Stacks::AppServer, &block)
  end

  def virtual_proxyserver(name, &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::VirtualProxyService], Stacks::ProxyServer, &block)
  end

  def virtual_sftpserver(name, &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::VirtualSftpService], Stacks::SftpServer, &block)
  end

  def virtual_rabbitmqserver(name = 'rabbitmq', &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::VirtualRabbitMQService], Stacks::RabbitMQServer, &block)
  end

  def virtual_bindserver(name, &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::VirtualBindService], Stacks::BindServer, &block)
  end

  def virtual_mailserver(name, &block)
    machineset_with(name, [Stacks::VirtualService, Stacks::VirtualMailService], Stacks::MailServer, &block)
  end

  def shadow_server(name, &block)
    machineset_with(name, [Stacks::ShadowServerCluster], Stacks::ShadowServer, &block)
  end

  def mongodb(name = 'mongodb', &block)
    machineset_with(name, [Stacks::MongoDBCluster], Stacks::MongoDBServer, &block)
  end

  def mysql_cluster(name = 'mysqldb', &block)
    machineset_with(name, [Stacks::MysqlCluster], Stacks::MysqlServer, &block)
  end

  def legacy_mysqldb(name = 'mysqldb', &block)
    machineset_with(name, [Stacks::LegacyMysqlCluster], Stacks::LegacyMysqlDBServer, &block)
  end

  def logstash(name = 'logstash', &block)
    machineset_with(name, [], Stacks::LogstashServer, &block)
  end

  def fmanalyticsanalysis(name = 'fmanalyticsanalysis', &block)
    machineset_with(name, [], Stacks::FmAnalyticsAnalysisServer, &block)
  end

  def fmanalyticsreporting(name = 'fmanalyticsreporting', &block)
    machineset_with(name, [], Stacks::FmAnalyticsReportingServer, &block)
  end

  def puppetmaster(name = "puppetmaster", &block)
    machineset_with(name, [], Stacks::PuppetMaster, &block)
  end

  def loadbalancer(&block)
    machineset_with('lb', [Stacks::LoadBalancerCluster], Stacks::LoadBalancer, &block)
  end

  def natserver(&block)
    machineset_with('nat', [], Stacks::NatServer, &block)
  end

  def elasticsearch(name = 'elasticsearch', &block)
    machineset_with(name, [], Stacks::ElasticSearchNode, &block)
  end

  def rate_limited_forward_proxy(name = 'rate_limited_forward_proxy', &block)
    machineset_with(name, [], Stacks::RateLimitedForwardProxyServer, &block)
  end

  def selenium_hub(name = 'hub-001', options = {})
    @definitions[name] = Stacks::Selenium::Hub.new(name, @definitions, options)
  end

  def selenium_node_cluster(name = 'segrid', &block)
    machineset_with(name, [Stacks::Selenium::Cluster], nil, &block)
  end

  def gold(name, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend Stacks::Gold
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

  def pentaho(name = 'pentaho', &block)
    machineset_with(name, [Stacks::AppService], Stacks::Pentaho, &block)
  end

  def quantapp(name = 'quantapp', &block)
    machineset_with(name, [], Stacks::QuantAppServer, &block)
  end

  def sensu(name = 'sensu', &block)
    machineset_with(name, [], Stacks::SensuServer, &block)
  end

  def standard(name, &block)
    machineset_with(name, [], Stacks::StandardServer, &block)
  end

  def [](key)
    @definitions[key]
  end

  private

  def machineset_with(name, extends, type, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend(Stacks::MachineGroup)
    extends.each { |e| machineset.extend(e) }
    machineset.type = type
    @definitions[name] = machineset
  end
end
