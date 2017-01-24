module Stacks::Services::CanBeNatted
  NatConfig = Struct.new(:inbound_enabled, :outbound_enabled, :public_network, :private_network, :tcp, :udp, :port_map)

  def self.extended(object)
    object.configure
  end

  attr_accessor :nat_config

  def configure
    @nat_config = NatConfig.new(false, false, :front, :prod, true, false, {})
  end

  def dnat_rules_for_dependency(location, requirements)
    rules = []
    requirements.each do |requirement|
      if requirement == :nat_to_host
        rules.concat(dnat_rules_for_host)
      elsif requirement == :nat_to_vip
        rules.concat(dnat_rules_for_vip(location))
      end
    end
    rules
  end

  def snat_rules_for_dependency(_location, requirements)
    rules = []
    requirements.each do |requirement|
      rules.concat(snat_rules_for_host) if requirement == :nat_to_host
    end
    rules
  end

  def dnat_rules_for_host
    rules = []
    if nat_config.inbound_enabled
      ports.each do |back_port|
        front_port = nat_config.port_map[back_port] || back_port

        children.each do |machine|
          public_uri = URI.parse("http://#{machine.hostname}.#{nat_config.public_network}.#{machine.domain}:#{front_port}")
          private_uri = URI.parse("http://#{machine.qualified_hostname(nat_config.private_network)}:#{back_port}")
          rules << Stacks::Services::Nat.new(public_uri, private_uri, nat_config.tcp, nat_config.udp)
        end
      end
    end
    rules
  end

  def dnat_rules_for_vip(location)
    rules = []
    fabric = environment.options[location]
    if nat_config.inbound_enabled
      @ports.map do |back_port|
        front_port = nat_config.port_map[back_port] || back_port
        front_uri = URI.parse("http://#{vip_fqdn(:front, fabric)}:#{front_port}")
        prod_uri = URI.parse("http://#{vip_fqdn(:prod, fabric)}:#{back_port}")
        rules << Stacks::Services::Nat.new(front_uri, prod_uri, nat_config.tcp, nat_config.udp)
      end
    end
    rules
  end

  def snat_rules_for_host
    rules = []
    if nat_config.outbound_enabled
      ports.map do |back_port|
        front_port = nat_config.port_map[back_port] || back_port

        children.each do |machine|
          public_uri = URI.parse("http://#{machine.hostname}.#{nat_config.public_network}.#{machine.domain}:#{front_port}")
          private_uri = URI.parse("http://#{machine.qualified_hostname(nat_config.private_network)}:#{back_port}")
          rules << Stacks::Services::Nat.new(private_uri, public_uri, nat_config.tcp, nat_config.udp)
        end
      end
    end
    rules
  end
end
