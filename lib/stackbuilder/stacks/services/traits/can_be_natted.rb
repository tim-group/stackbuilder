module Stacks::Services::CanBeNatted
  NatConfig = Struct.new(:inbound_enabled, :public_network, :private_network, :tcp, :udp, :port_map)

  def self.extended(object)
    object.configure
  end

  attr_accessor :nat_config

  def configure
    @nat_config = NatConfig.new(false, :front, :prod, true, false, {})
  end

  def dnat_rules(_location)
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
end
