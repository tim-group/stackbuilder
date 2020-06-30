module Stacks::Services::VpnService
  def self.extended(object)
    object.configure
  end

  def configure
    @ports = [500, 4500]
    add_vip_network :mgmt
    @nat_config.tcp = false
    @nat_config.udp = true
  end

  def load_balanced_service?
    false
  end
end
