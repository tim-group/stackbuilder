module Stacks::AppService
  def self.extended(object)
    object.configure
  end

  attr_accessor :application, :ehcache, :sso_port, :ajp_port, :jvm_args, :idea_positions_exports
  attr_accessor :enable_tomcat_session_replication

  def configure
    @ehcache = false
    @ports = [8000]
    @sso_port = nil
    @ajp_port = nil
    @jvm_args = nil
    @idea_positions_exports = false
    @disable_http_lb_hack = false
    @enable_tomcat_session_replication = false
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

  def enable_tomcat_session_replication
    @enable_tomcat_session_replication = true
  end

  def disable_http_lb_hack
    @disable_http_lb_hack = true
  end

  def set_jvm_args(jvm_args)
    @jvm_args = jvm_args
  end

  def config_params(_dependant)
    { "#{application.downcase}.url" => "http://#{vip_fqdn(:prod)}:8000" }
  end

  def to_loadbalancer_config
    config = lb_config
    unless @sso_port.nil?
      if @disable_http_lb_hack
        config[vip_fqdn(:prod)]['type'] = 'sso_app'
      else
        config[vip_fqdn(:prod)]['type'] = 'http_and_sso_app'
      end
    end
    config
  end
end
