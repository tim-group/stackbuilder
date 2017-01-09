require 'stackbuilder/stacks/namespace'

module Stacks::Services::LogstashCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :role
  attr_accessor :instances
  attr_accessor :ports

  def configure
    @vip_networks = [:prod]
    @ports = []
    @role = :receiver
    @instances = 1
  end

  def receiver_nodes
    receivers = children.reject { |nodes| !nodes.role?(:receiver) }
    receivers.collect(&:prod_fqdn)
  end

  def indexer_nodes
    receivers = children.reject { |nodes| !nodes.role?(:indexer) }
    receivers.collect(&:prod_fqdn)
  end

  def vip_fqdn(network, fabric)
    domain = environment.domain(fabric, network)
    "#{environment.name}-#{name}-vip.#{domain}"
  end

  def to_loadbalancer_config(_location, fabric)
    return {} if !receiver_nodes
    vip_nets = @vip_networks.select do |vip_network|
      ![:front].include? vip_network
    end

    lb_config = {}

    vip_nets.each do |vip_net|
      lb_config[vip_fqdn(vip_net, fabric)] = {
        'type'         => 'http',
        'ports'        => @ports,
        'realservers'  => {
          'blue' => receiver_nodes.sort
        }
      }
    end
    lb_config
  end
end
