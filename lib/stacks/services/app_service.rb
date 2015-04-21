module Stacks::Services::AppService
  attr_accessor :ajp_port
  attr_accessor :application
  attr_accessor :ehcache
  attr_accessor :idea_positions_exports
  attr_accessor :jvm_args
  attr_accessor :sso_port
  attr_accessor :tomcat_session_replication

  def self.extended(object)
    object.configure
  end

  def configure
    @ajp_port = nil
    @disable_http_lb_hack = false
    @ehcache = false
    @idea_positions_exports = false
    @jvm_args = nil
    @ports = [8000]
    @sso_port = nil
    @tomcat_session_replication = false
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
    @tomcat_session_replication = true
  end

  def disable_http_lb_hack
    @disable_http_lb_hack = true
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
