module Stacks::VirtualNameService
  def self.extended(object)
    object.configure()
  end

  def configure()
    @ports = [53]
  end

  def config_params(dependant)
#    config = {
#      "#{application.downcase}.url" => "http://#{vip_fqdn}:8000"
#    }
  end
end
