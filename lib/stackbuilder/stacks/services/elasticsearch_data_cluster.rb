require 'stackbuilder/stacks/namespace'

module Stacks::Services::ElasticsearchDataCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :instances
  attr_accessor :ports
  attr_accessor :is_xpack_monitoring_destination

  def configure
    @ports = [9200]
    @instances = 2
    @is_xpack_monitoring_destination = false
  end

  def xpack_monitoring_destination
    @is_xpack_monitoring_destination = true
  end

  def kibana_hosts
    virtual_services_that_depend_on_me.select do |service|
      service.is_a?(Stacks::Services::KibanaCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end

  def logstash_indexer_hosts
    virtual_services_that_depend_on_me.select do |service|
      service.is_a?(Stacks::Services::LogstashIndexerCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end

  def config_params(_dependant, fabric, _dependent_instance)
    { "#{name}.url" => "http://#{vip_fqdn(:prod, environment.primary_site)}:9200" }
  end

  def logstash_receiver_hosts
    virtual_services_that_depend_on_me.select do |service|
      service.is_a?(Stacks::Services::LogstashReceiverCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end

  def elasticsearch_master_hosts
    virtual_services_that_i_depend_on.select do |service|
      service.is_a?(Stacks::Services::ElasticsearchMasterCluster)
    end.map do |service|
      service.children.map(&:prod_fqdn)
    end.flatten.sort
  end

  def elasticsearch_minimum_master_nodes
    (elasticsearch_master_hosts.length.to_f / 2).ceil
  end

  def other_elasticsearch_data_hosts(this_servers_hostname)
    children.select do |child|
      child.mgmt_fqdn != this_servers_hostname
    end.map(&:prod_fqdn).flatten.sort
  end

  def to_loadbalancer_config(location, fabric)
    config = {}
    config[vip_fqdn(:prod, fabric)] = {
      'type'         => 'elasticsearch_data',
      'ports'        => @ports,
      'realservers'  => {
        'blue' => realservers(location).map { |server| server.qualified_hostname(:prod) }.sort
      },
      'healthchecks' => [{
        'healthcheck' => 'TCP_CHECK',
        'connect_timeout' => '5'
      }]
    }
    config
  end
end
