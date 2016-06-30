require 'stackbuilder/stacks/services/namespace'
require 'stackbuilder/stacks/gold'
require 'stackbuilder/stacks/namespace'

class Stacks::CustomServices
  attr_reader :name

  include Stacks::MachineDefContainer

  def initialize(name)
    @name = name
    @definitions = {}
  end

  def type_of?
    :custom_service
  end

  def identity
    "#{environment.name}_#{name.to_sym}"
  end

  def app_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::AppService],
                    Stacks::Services::AppServer, &block)
  end

  def standalone_app_service(name, &block)
    machineset_with(name, [Stacks::Services::AppService], Stacks::Services::AppServer, &block)
  end

  def proxy_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualProxyService],
                    Stacks::Services::ProxyServer, &block)
  end

  def sftp_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualSftpService],
                    Stacks::Services::SftpServer, &block)
  end

  def rabbitmq_cluster(name = 'rabbitmq', &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::RabbitMQCluster],
                    Stacks::Services::RabbitMQServer, &block)
  end

  def bind_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualBindService],
                    Stacks::Services::BindServer, &block)
  end

  def mail_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualMailService],
                    Stacks::Services::MailServer, &block)
  end

  def external_service(name, &block)
    machineset_with(name, [Stacks::Services::ExternalServerCluster], Stacks::Services::ExternalServer, &block)
  end

  def mongodb_cluster(name = 'mongodb', &block)
    machineset_with(name, [Stacks::Services::MongoDBCluster], Stacks::Services::MongoDBServer, &block)
  end

  def mysql_cluster(name = 'mysqldb', &block)
    machineset_with(name, [Stacks::Services::MysqlCluster], Stacks::Services::MysqlServer, &block)
  end

  def legacy_mysql_cluster(name = 'mysqldb', &block)
    machineset_with(name, [Stacks::Services::LegacyMysqlCluster], Stacks::Services::LegacyMysqlDBServer, &block)
  end

  def fmanalyticsanalysis_service(name = 'fmanalyticsanalysis', &block)
    machineset_with(name, [], Stacks::Services::FmAnalyticsAnalysisServer, &block)
  end

  def fmanalyticsreporting_service(name = 'fmanalyticsreporting', &block)
    machineset_with(name, [], Stacks::Services::FmAnalyticsReportingServer, &block)
  end

  def puppetserver_cluster(name, &block)
    machineset_with(name, [Stacks::Services::PuppetserverCluster], Stacks::Services::Puppetserver, &block)
  end

  def puppetdb_cluster(name, &block)
    machineset_with(name, [Stacks::Services::PuppetdbCluster], Stacks::Services::Puppetdb, &block)
  end

  def loadbalancer_service(&block)
    machineset_with('lb', [Stacks::Services::LoadBalancerCluster], Stacks::Services::LoadBalancer, &block)
  end

  def nat_service(&block)
    machineset_with('nat', [Stacks::Services::NatCluster], Stacks::Services::NatServer, &block)
  end

  def elasticsearch_cluster(name = 'elasticsearch', &block)
    machineset_with(name, [Stacks::Services::ElasticsearchCluster], Stacks::Services::ElasticsearchNode, &block)
  end

  def logstash_cluster(name = 'logstash', &block)
    machineset_with(name, [Stacks::Services::LogstashCluster], Stacks::Services::LogstashServer, &block)
  end

  def rate_limited_forward_proxy_service(name = 'rate_limited_forward_proxy', &block)
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

  def cislave(name, &block)
    machineset_with(name, [], Stacks::Services::CiSlave, &block)
  end

  def eventstore_cluster(name = 'eventstore', &block)
    machineset_with(name, [Stacks::Services::EventStoreCluster], Stacks::Services::EventStoreServer, &block)
  end

  def pentaho_service(name = 'pentaho_server', &block)
    machineset_with(name, [Stacks::Services::AppService], Stacks::Services::PentahoServer, &block)
  end

  def quantapp_service(name = 'quantapp', &block)
    machineset_with(name, [Stacks::Services::AppService], Stacks::Services::QuantAppServer, &block)
  end

  def standard_service(name, &block)
    machineset_with(name, [], Stacks::Services::StandardServer, &block)
  end

  def vpn_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VpnService],
                    Stacks::Services::VpnServer, &block)
  end

  def [](key)
    @definitions[key]
  end

  private

  def machineset_with(name, extends, type, &block)
    machineset = Stacks::MachineSet.new(name, &block)
    machineset.extend(Stacks::Dependencies)
    extends.each { |e| machineset.extend(e) }
    machineset.type = type
    @definitions[name] = machineset
  end
end
