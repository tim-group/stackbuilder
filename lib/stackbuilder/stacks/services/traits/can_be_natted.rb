module Stacks::Services::CanBeNatted
  NatConfig = Struct.new(:inbound_enabled, :outbound_enabled, :public_network, :private_network, :tcp, :udp, :port_map) do
    def create_rule(environment, type, hostname, site, front_port, back_port)
      public_uri = uri(hostname, environment.domain(site, public_network), front_port)
      private_uri = uri(hostname, environment.domain(site, private_network), back_port)

      case type
      when :dnat
        Stacks::Services::NatRule.new(public_uri, private_uri, tcp, udp)
      when :snat
        Stacks::Services::NatRule.new(private_uri, public_uri, tcp, udp)
      end
    end

    private

    def uri(hostname, domain, port)
      URI.parse("http://#{hostname}.#{domain}:#{port}")
    end
  end

  def self.extended(object)
    object.configure
  end

  attr_accessor :dnat_config, :snat_config

  def configure
    @dnat_config = NatConfig.new(false, false, :front, :prod, true, false, {})
    @snat_config = NatConfig.new(false, false, :front, :prod, true, false, {})
  end

  def configure_dnat(public_network, private_network, tcp, udp, portmap = {})
    @dnat_config = NatConfig.new(true, false, public_network, private_network, tcp, udp, portmap)
  end

  def configure_snat(public_network, private_network, tcp, udp, portmap = {})
    @snat_config = NatConfig.new(false, true, public_network, private_network, tcp, udp, portmap)
  end

  def calculate_nat_rules(type, site, requirements)
    hostnames = requirements.map do |requirement|
      case requirement
      when :nat_to_host
        children.map(&:hostname)
      when :nat_to_vip
        ["#{environment.name}-#{name}-vip"]
      end
    end.flatten

    case type
    when :dnat
      dnat_config.inbound_enabled ? create_rules_for_hosts(dnat_config, hostnames, site, :dnat) : []
    when :snat
      snat_config.outbound_enabled ? create_rules_for_hosts(snat_config, hostnames, site, :snat) : []
    end
  end

  private

  def create_rules_for_hosts(config, hostnames, site, type)
    ports.map do |back_port|
      hostnames.map do |hostname|
        front_port = config.port_map[back_port] || back_port
        config.create_rule(environment, type, hostname, site, front_port, back_port)
      end
    end.flatten
  end
end
