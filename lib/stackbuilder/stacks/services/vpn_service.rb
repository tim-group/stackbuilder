module Stacks::Services::VpnService
  def self.extended(object)
    object.configure
  end

  def configure
    @ports = {
      'isakmp' => {
        'port' => 500,
        'protocol' => 'udp'
      },
      'isakmp-nat-t' => {
        'port' => 4500,
        'protocol' => 'udp'
      }
    }
    add_vip_network :mgmt
    @nat_config.tcp = false
    @nat_config.udp = true
  end

  def load_balanced_service?
    false
  end
end
