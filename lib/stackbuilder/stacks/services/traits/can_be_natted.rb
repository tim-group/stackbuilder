module Stacks::Services::CanBeNatted
  NatConfig = Struct.new(:inbound_enabled, :outbound_enabled, :public_network, :private_network, :tcp, :udp, :port_map)

  def self.extended(object)
    object.configure
  end

  attr_accessor :dnat_config, :snat_config
  attr_accessor :nat_config # backwards compatibility

  def configure
    @nat_config = NatConfig.new(false, false, :front, :prod, true, false, {})
    @dnat_config = @nat_config
    @snat_config = @nat_config
  end

  def configure_dnat(public_network, private_network, tcp, udp, portmap = {})
    @dnat_config = NatConfig.new(true, false, public_network, private_network, tcp, udp, portmap)
  end

  def configure_snat(public_network, private_network, tcp, udp, portmap = {})
    @snat_config = NatConfig.new(false, true, public_network, private_network, tcp, udp, portmap)
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
    if dnat_config.inbound_enabled
      ports.each do |back_port|
        front_port = dnat_config.port_map[back_port] || back_port

        children.each do |machine|
          public_uri = uri_for_host(machine, dnat_config.public_network, front_port)
          private_uri = uri_for_host(machine, dnat_config.private_network, back_port)
          rules << Stacks::Services::Nat.new(public_uri, private_uri, dnat_config.tcp, dnat_config.udp)
        end
      end
    end
    rules
  end

  def dnat_rules_for_vip(location)
    rules = []
    fabric = environment.options[location]
    if dnat_config.inbound_enabled
      ports.map do |back_port|
        front_port = dnat_config.port_map[back_port] || back_port
        public_uri = uri_for_vip(fabric, front_port, vip_hostname, dnat_config.public_network)
        private_uri = uri_for_vip(fabric, back_port, vip_hostname, dnat_config.private_network)
        rules << Stacks::Services::Nat.new(public_uri, private_uri, dnat_config.tcp, dnat_config.udp)
      end
    end
    rules
  end

  def snat_rules_for_host
    rules = []
    if snat_config.outbound_enabled
      ports.map do |back_port|
        front_port = snat_config.port_map[back_port] || back_port
        children.each do |machine|
          public_uri = uri_for_host(machine, snat_config.public_network, front_port)
          private_uri = uri_for_host(machine, snat_config.private_network, back_port)
          rules << Stacks::Services::Nat.new(private_uri, public_uri, snat_config.tcp, snat_config.udp)
        end
      end
    end
    rules
  end

  def snat_rules_for_vip(location)
    rules = []
    fabric = environment.options[location]
    if self.snat_config.outbound_enabled
      ports.map do |back_port|
        front_port = snat_config.port_map[back_port] || back_port
        public_uri = uri_for_vip(fabric, front_port, vip_hostname, snat_config.public_network)
        private_uri = uri_for_vip(fabric, back_port, vip_hostname, snat_config.private_network)
        rules << Stacks::Services::Nat.new(private_uri, public_uri, snat_config.tcp, snat_config.udp)
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
