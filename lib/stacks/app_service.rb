module Stacks::AppService
  def self.extended(object)
    object.configure()
  end

  attr_accessor :application, :ehcache, :sso, :jvm_args

  def configure()
    @ehcache = false
    @ports = [8000]
    @sso = false
    @jvm_args = nil
  end

  def enable_ehcache
    @ehcache = true
  end

  def enable_sso
    @sso = true
  end

  def config_params(dependant)
    config = {
      "#{application.downcase}.url" => "http://#{vip_fqdn(:prod)}:8000"
    }
  end

  def to_loadbalancer_config
    config = lb_config
    config[self.vip_fqdn(:prod)]['type'] = 'sso_app' if @sso
    config
  end

end
