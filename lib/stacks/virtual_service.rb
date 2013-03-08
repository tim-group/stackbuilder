require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/server'
require 'stacks/nat'

class Stacks::VirtualService < Stacks::MachineDefContainer
  attr_reader :name
  attr_reader :environment
  attr_reader :nat
  attr_reader :domain
  attr_reader :fabric
  attr_accessor :application
  attr_accessor :groups
  attr_accessor :instances

  def initialize(name)
    @name = name
    @definitions = {}
    @nat=false
    @groups = ['blue']
    @instances = 2
  end

  def bind_to(environment)
    @environment = environment
    @fabric = environment.options[:primary]
    @domain = "#{@fabric}.net.local"
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = Stacks::Server.new(self, index)
      server.group=groups[i%groups.size]
    end
    super(environment)
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
      :fabric => @fabric,
      :networks => networks,
      :qualified_hostnames => qualified_hostnames
    }
  end

  def enable_nat
    @nat = true
  end

  def nat_rule
    return Stacks::Nat.new(vip_front_fqdn, vip_fqdn)
  end
end
