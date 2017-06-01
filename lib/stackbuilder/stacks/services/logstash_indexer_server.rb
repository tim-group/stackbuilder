require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::LogstashIndexerServer < Stacks::MachineDef
  attr_reader :logstash_cluster

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @logstash_cluster = virtual_service
  end

  def stackname
    @logstash_cluster.name
  end

  def to_enc
    enc = super()

    rabbitmq_config = @logstash_cluster.rabbitmq_config
    enc.merge!('role::logstash_indexer' => {
                 'elasticsearch_cluster_address' => @logstash_cluster.elasticsearch_data_address(@fabric),
                 'elasticsearch_data_hosts'      => @logstash_cluster.elasticsearch_data_hosts,
                 'logstash_receivers'            => @logstash_cluster.logstash_receiver_hosts,
                 'rabbitmq_central_username'     => rabbitmq_config.username,
                 'rabbitmq_central_password_key' => rabbitmq_config.password_hiera_key,
                 'rabbitmq_central_exchange'     => @logstash_cluster.exchange,
                 'rabbitmq_central_hosts'        => @logstash_cluster.rabbitmq_logging_hosts
               },
               'server::default_new_mgmt_net_local' => nil)
    enc
  end
end
