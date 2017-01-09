require 'stackbuilder/stacks/namespace'

module Stacks::Services::ElasticsearchCluster
  def self.extended(object)
    object.configure
  end

  attr_accessor :cluster_name
  attr_accessor :master_nodes
  attr_accessor :data_nodes
  attr_accessor :marvel_target
  attr_accessor :data_storage

  def configure
    @cluster_name = @name
    @master_nodes = 3
    @data_nodes = 4
    @vip_networks = [:prod]
    @ports = [9200]
    @marvel_target = ''
    @data_storage = '500G'
  end

  def instantiate_machines(environment)
    server_index = 0
    @master_nodes.times do
      instantiate_machine(server_index += 1, environment, environment.sites.first, :master, '-master')
    end
    server_index = 0
    @data_nodes.times do
      instantiate_machine(server_index += 1, environment, environment.sites.first, :data, '-data')
    end
  end

  def clazz
    'elasticsearchcluster'
  end

  def cluster_name(environment)
    "#{environment.name}-#{@cluster_name}"
  end

  def nodes_with_role(role)
    nodes = children.reject { |node| !node.role?(role) }
    nodes.collect(&:prod_fqdn)
  end

  def to_vip_spec(location)
    fabric = environment.options[location]
    qualified_hostnames = Hash[@vip_networks.sort.map { |network| [network, vip_fqdn(network, fabric)] }]
    {
      :hostname => "#{environment.name}-#{name}",
      :fabric => fabric,
      :networks => @vip_networks,
      :qualified_hostnames => qualified_hostnames
    }
  end

  def marvel_target_vip
    vip_fqdn(:prod, @marvel_target) unless @marvel_target.empty?
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
