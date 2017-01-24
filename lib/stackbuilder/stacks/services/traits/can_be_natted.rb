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
    requirements.map do |requirement|
      if requirement == :nat_to_host
        dnat_rules_for_host
      elsif requirement == :nat_to_vip
        dnat_rules_for_vip(location)
      end
    end.flatten
  end

  def snat_rules_for_dependency(location, requirements)
    requirements.map do |requirement|
      if requirement == :nat_to_host
        snat_rules_for_host
      elsif requirement == :nat_to_vip
        snat_rules_for_vip(location)
      end
    end.flatten
  end

  def dnat_rules_for_host
    rules = []
    if nat_config.inbound_enabled
      ports.each do |back_port|
        front_port = nat_config.port_map[back_port] || back_port

        children.each do |machine|
          public_uri = uri_for_host(machine, nat_config.public_network, front_port)
          private_uri = uri_for_host(machine, nat_config.private_network, back_port)
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
        public_uri = uri_for_vip(fabric, front_port, vip_hostname, nat_config.public_network)
        private_uri = uri_for_vip(fabric, back_port, vip_hostname, nat_config.private_network)
        rules << Stacks::Services::Nat.new(public_uri, private_uri, nat_config.tcp, nat_config.udp)
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
          public_uri = uri_for_host(machine, nat_config.public_network, front_port)
          private_uri = uri_for_host(machine, nat_config.private_network, back_port)
          rules << Stacks::Services::Nat.new(private_uri, public_uri, nat_config.tcp, nat_config.udp)
        end
      end
    end
    rules
  end

  def snat_rules_for_vip(location)
    rules = []
    fabric = environment.options[location]
    if nat_config.outbound_enabled
      ports.map do |back_port|
        front_port = nat_config.port_map[back_port] || back_port
        public_uri = uri_for_vip(fabric, front_port, vip_hostname, nat_config.public_network)
        private_uri = uri_for_vip(fabric, back_port, vip_hostname, nat_config.private_network)
        rules << Stacks::Services::Nat.new(private_uri, public_uri, nat_config.tcp, nat_config.udp)
      end
    end
    rules
  end

  private

  def vip_hostname
    "#{environment.name}-#{name}-vip"
  end

  def uri_for_vip(fabric, front_port, hostname, public_network)
    URI.parse("http://#{hostname}.#{environment.domain(fabric, public_network)}:#{front_port}")
  end

  def uri_for_host(machine, network, port)
    URI.parse("http://#{machine.hostname}.#{network}.#{machine.domain}:#{port}")
  end
end
