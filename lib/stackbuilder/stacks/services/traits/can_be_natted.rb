module Stacks::Services::CanBeNatted
  NatConfig = Struct.new(:dnat_enabled, :snat_enabled, :public_network, :private_network, :tcp, :udp) do
    def create_rule(environment, type, hostname, site, port)
      public_uri = uri(hostname, environment.domain(site, public_network), port)
      private_uri = uri(hostname, environment.domain(site, private_network), port)

      case type
      when :dnat
        Stacks::Services::NatRule.new(public_uri, private_uri, tcp, udp)
      when :snat
        Stacks::Services::NatRule.new(private_uri, public_uri, tcp, udp)
      end
    end

    def networks
      [public_network, private_network]
    end

    private

    def uri(hostname, domain, port)
      URI.parse("http://#{hostname}.#{domain}:#{port}")
    end
  end

  def self.extended(object)
    object.configure
  end

  attr_accessor :nat_config

  def configure
    @nat_config = NatConfig.new(false, false, :front, :prod, true, false)
  end

  def configure_nat(dnat_enabled, snat_enabled, public_network, private_network, tcp, udp)
    @nat_config = NatConfig.new(dnat_enabled, snat_enabled, public_network, private_network, tcp, udp)
  end

  def configure_dnat(public_network, private_network, tcp, udp)
    configure_nat(true, nat_config.snat_enabled, public_network, private_network, tcp, udp)
  end

  def configure_snat(public_network, private_network, tcp, udp)
    configure_nat(nat_config.dnat_enabled, true, public_network, private_network, tcp, udp)
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
      nat_config.dnat_enabled ? create_rules_for_hosts(hostnames, site, :dnat) : []
    when :snat
      nat_config.snat_enabled ? create_rules_for_hosts(hostnames, site, :snat) : []
    end
  end

  private

  def create_rules_for_hosts(hostnames, site, type)
    ports.map do |port|
      hostnames.map do |hostname|
        nat_config.create_rule(environment, type, hostname, site, port)
      end
    end.flatten
  end
end
