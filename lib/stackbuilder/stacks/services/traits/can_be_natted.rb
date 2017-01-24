module Stacks::Services::CanBeNatted

  NatConfig = Struct.new(:inbound_enabled, :public_network, :private_network, :tcp, :udp)

  def self.extended(object)
    object.configure
  end


  attr_accessor :nat_config

  def configure
    @nat_config = NatConfig.new(false, :front, :prod, true, false)
  end

end