require 'stackbuilder/stacks/services/namespace'
require 'stackbuilder/stacks/gold'
require 'stackbuilder/stacks/namespace'

class Stacks::CustomServices
  attr_reader :name
  attr_reader :k8s_machinesets

  include Stacks::MachineDefContainer

  def initialize(name, environment)
    @name = name
    @definitions = {}
    @k8s_machinesets = {}
    @environment = environment
  end

  def type_of?
    :custom_service
  end

  def identity
    "#{environment.name}_#{name.to_sym}"
  end

  def service_in_kubernetes?(name, properties)
    fail("app_service '#{name}' does not specify kubernetes property for environment '#{@environment.name}'. \
If any environments are specified then all environments where the stack is instantiated must \
be specified.") if properties.is_a?(Hash) && properties[:kubernetes].is_a?(Hash) && !properties[:kubernetes].key?(@environment.name)

    fail("app_service '#{name}' kubernetes property for environment '#{@environment.name}' is not a boolean.") if
      properties.is_a?(Hash) && properties[:kubernetes].is_a?(Hash) && ![true, false].include?(properties[:kubernetes][@environment.name])

    properties.is_a?(Hash) &&
      ((properties[:kubernetes].is_a?(Hash) && properties[:kubernetes][@environment.name] == true) ||
        (properties[:kubernetes] == true))
  end

  def app_service(name, properties = {}, &block)
    if service_in_kubernetes?(name, properties)
      k8s_machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::AppService], &block)
    else
      machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::AppService],
                      Stacks::Services::AppServer, &block)
    end
  end

  def standalone_app_service(name, properties = {}, &block)
    if service_in_kubernetes?(name, properties)
      k8s_machineset_with(name, [Stacks::Services::AppService], &block)
    else
      machineset_with(name, [Stacks::Services::AppService], Stacks::Services::AppServer, &block)
    end
  end

  def proxy_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualProxyService],
                    Stacks::Services::ProxyServer, &block)
  end

  def sftp_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualSftpService],
                    Stacks::Services::SftpServer, &block)
  end

  def ssh_service(name, &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::VirtualSshService],
                    Stacks::Services::StandardServer, &block)
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

  def mysql_cluster(name = 'mysqldb', &block)
    machineset_with(name, [Stacks::Services::MysqlCluster], Stacks::Services::MysqlServer, &block)
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

  def elasticsearch_data(name = 'elasticsearch_data', &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::ElasticsearchDataCluster], Stacks::Services::ElasticsearchDataServer, &block)
  end

  def elasticsearch_master(name = 'elasticsearch_master', &block)
    machineset_with(name, [Stacks::Services::ElasticsearchMasterCluster], Stacks::Services::ElasticsearchMasterServer, &block)
  end

  def logstash_receiver(name = 'logstash_receiver', &block)
    machineset_with(name, [Stacks::Services::LogstashReceiverCluster], Stacks::Services::LogstashReceiverServer, &block)
  end

  def logstash_indexer(name = 'logstash_indexer', &block)
    machineset_with(name, [Stacks::Services::LogstashIndexerCluster], Stacks::Services::LogstashIndexerServer, &block)
  end

  def kibana(name = 'kibana', &block)
    machineset_with(name, [Stacks::Services::VirtualService, Stacks::Services::KibanaCluster], Stacks::Services::KibanaServer, &block)
  end

  def rabbitmq_logging(name = 'rabbitmq_logging', &block)
    machineset_with(name, [Stacks::Services::RabbitMqLoggingCluster], Stacks::Services::RabbitMqLoggingServer, &block)
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
    machineset = Stacks::MachineSet.new(name, self, &block)
    machineset.extend Stacks::Gold
    @definitions[name] = machineset
  end

  def cislave(name, &block)
    machineset_with(name, [], Stacks::Services::CiSlave, &block)
  end

  def eventstore_cluster(name = 'eventstore', &block)
    machineset_with(name, [Stacks::Services::EventStoreCluster], Stacks::Services::EventStoreServer, &block)
  end

  def kafka_cluster(name = 'kafka', &block)
    machineset_with(name, [Stacks::Services::KafkaCluster], Stacks::Services::KafkaServer, &block)
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

  alias_method :orig_bind_to, :bind_to
  def bind_to(environment)
    orig_bind_to(environment)
    k8s_machinesets.values.each { |s| s.bind_to(environment) }
  end

  private

  def machineset_with(name, extends, type, &block)
    machineset = Stacks::MachineSet.new(name, self, &block)
    machineset.extend(Stacks::Dependencies)
    extends.each { |e| machineset.extend(e) }
    machineset.type = type
    @definitions[name] = machineset
  end

  def k8s_machineset_with(name, extends, &block)
    machineset = Stacks::MachineSet.new(name, self, &block)
    machineset.extend(Stacks::Dependencies)
    extends.each { |e| machineset.extend(e) }
    machineset.kubernetes = true
    @k8s_machinesets[name] = machineset
  end
end
