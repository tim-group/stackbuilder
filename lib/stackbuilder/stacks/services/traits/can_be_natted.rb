module Stacks::Services::CanBeNatted

  NatConfig = Struct.new(:inbound_enabled, :public_network, :private_network, :tcp, :udp, :port_map)

  def self.extended(object)
    object.configure
  end


  attr_accessor :nat_config

  def configure
    @nat_config = NatConfig.new(false, :front, :prod, true, false, {})
  end

  def dnat_rules(location)
    rules = []
    if self.nat_config.inbound_enabled
      self.ports.each do |back_port|
        front_port = self.nat_config.port_map[back_port] || back_port

        self.children.each do |machine|
          public_uri = URI.parse("http://#{machine.hostname}.#{self.nat_config.public_network}.#{machine.domain}:#{front_port}")
          private_uri = URI.parse("http://#{machine.qualified_hostname(self.nat_config.private_network)}:#{back_port}")
          rules << Stacks::Services::Nat.new(public_uri, private_uri, self.nat_config.tcp, self.nat_config.udp)
        end
      end
    end
    rules

  end
end