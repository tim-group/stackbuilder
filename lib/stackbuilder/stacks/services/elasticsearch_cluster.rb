require 'stackbuilder/stacks/namespace'

module Stacks::Services::ElasticsearchCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :cluster_name
  attr_accessor :master_nodes
  attr_accessor :data_nodes
  attr_accessor :tribe_nodes
  attr_accessor :marvel_target
  attr_accessor :data_storage

  def configure
    @cluster_name = @name
    @master_nodes = 3
    @data_nodes = 4
    @tribe_nodes = 1
    @vip_networks = [:prod]
    @ports = [9200]
    @marvel_target = ''
    @data_storage = '500G'
  end

  def instantiate_machine(name, type, i, environment, location)
    index = sprintf("%03d", i)
    server_name = "#{name}-#{type}-#{index}"
    server = @type.new(server_name, i, self, type, location)
    server.group = groups[i % groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    @definitions["#{server_name}-#{location}"] = server
  end

  def instantiate_machines(environment)
    i = 0
    @master_nodes.times do
      instantiate_machine(name, :master, i += 1, environment, :primary_site)
    end

    i = 0
    @data_nodes.times do
      instantiate_machine(name, :data, i += 1, environment, :primary_site)
    end

    i = 0
    @tribe_nodes.times do
      instantiate_machine(name, :tribe, i += 1, environment, :primary_site)
    end
  end

  def clazz
    'elasticsearchcluster'
  end

  def nodes_with_role(role)
    nodes = children.reject { |node| !node.role?(role) }
    nodes.collect(&:prod_fqdn)
  end

  def all_nodes
    children.collect(&:prod_fqdn)
  end

  def vip_fqdn(network, fabric)
    domain = environment.domain(fabric, network)
    "#{environment.name}-#{name}-vip.#{domain}"
  end

  def to_loadbalancer_config(_location, fabric)
    vip_nets = @vip_networks.select do |vip_network|
      ![:front].include? vip_network
    end

    lb_config = {}

    vip_nets.each do |vip_net|
      lb_config[vip_fqdn(vip_net, fabric)] = {
        'type'         => 'http',
        'ports'        => @ports,
        'realservers'  => {
          'blue' => nodes_with_role(:data).sort
        }
      }
    end
    lb_config
  end
end
