module Stacks::Services::VpnService
  def self.extended(object)
    object.configure
  end

  def configure
    @ports = [500, 4500]
    @tcp = false
    @udp = true
  end

  def load_balanced_service?
    false
  end
end
