require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

class Stacks::VirtualService < Stacks::MachineDefContainer
  attr_reader :name
  attr_reader :environment
  attr_reader :nat #proxy
  attr_reader :domain
  attr_reader :fabric
  attr_accessor :port
  attr_accessor :instances

  def initialize(name, &config_block)
    @name = name
    @definitions = {}
    @nat=false
    @instances = 2
    @port = 8000
    @config_block = config_block
  end

  def bind_to(environment)
    @environment = environment
    @fabric = environment.options[:primary_site]
    @domain = "#{@fabric}.net.local"
    super(environment)
    self.instance_eval(&@config_block) unless @config_block.nil?
  end

  def clazz
    return 'virtualservice'
  end

  def realservers
    return @definitions.values
  end

  def vip_fqdn
    "#{environment.name}-#{name}-vip.#{@domain}"
  end

  def vip_front_fqdn
    "#{environment.name}-#{name}-vip.front.#{@domain}"
  end

  def to_vip_spec
    networks = (nat==true)? [:prod, :front]: [:prod]
    qualified_hostnames = Hash[networks.map do |network|
      pair = nil
      if network==:prod
        pair = [network,vip_fqdn]
      end
      if network==:front
        pair = [network, vip_front_fqdn]
      end
      pair
    end]
    {
      :hostname => "#{environment.name}-#{name}",
      :fabric => @fabric,
      :networks => networks,
      :qualified_hostnames => qualified_hostnames
    }
  end

  def enable_nat
    @nat = true
  end

  def nat_rule
    front_uri = URI.parse("http://#{vip_front_fqdn}")
    prod_uri = URI.parse("http://#{vip_fqdn}:#{port}")
    return Stacks::Nat.new(front_uri, prod_uri)
  end
end
