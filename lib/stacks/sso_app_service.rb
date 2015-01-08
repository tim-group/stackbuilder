module Stacks::SsoAppService
  def self.extended(object)
    object.configure()
  end

  attr_accessor :application, :ehcache

  def configure()
    @ehcache = false
    @ports = [8000]
  end

  def enable_ehcache
    @ehcache = true
  end

  def config_params(dependant)
    config = {
      "#{application.downcase}.url" => "http://#{vip_fqdn(:prod)}:8000"
    }
  end
end
