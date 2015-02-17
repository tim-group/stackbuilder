module Stacks::AppService
  def self.extended(object)
    object.configure()
  end

  attr_accessor :application, :ehcache, :sso_port, :ajp_port, :jvm_args

  def configure()
    @ehcache = false
    @ports = [8000]
    @sso_port = nil
    @ajp_port = nil
    @jvm_args = nil
  end

  def enable_ehcache
    @ehcache = true
  end

  def enable_sso(sso_port = '8443')
    @sso_port = sso_port
  end

  def enable_ajp(ajp_port = '8009')
    @ajp_port = ajp_port
  end

  def set_jvm_args(jvm_args)
    @jvm_args = jvm_args
  end

  def config_params(dependant)
    config = {
      "#{application.downcase}.url" => "http://#{vip_fqdn(:prod)}:8000"
    }
  end

  def to_loadbalancer_config
    config = lb_config
    config[self.vip_fqdn(:prod)]['type'] = 'sso_app' unless @sso_port.nil?
    config
  end

end
