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
    @one_instance_in_lb = false
    @sso_port = nil
    @tomcat_session_replication = false
  end

  def enable_ehcache
    @ehcache = true
  end

  # rubocop:disable Style/TrivialAccessors
  def enable_sso(sso_port = '8443')
    @sso_port = sso_port
  end
  # rubocop:enable Style/TrivialAccessors

  # rubocop:disable Style/TrivialAccessors
  def enable_ajp(ajp_port = '8009')
    @ajp_port = ajp_port
  end
  # rubocop:enable Style/TrivialAccessors

  def enable_tomcat_session_replication
    @tomcat_session_replication = true
  end

  def disable_http_lb_hack
    @disable_http_lb_hack = true
  end

  def config_params(_dependant, location)
    { "#{application.downcase}.url" => "http://#{vip_fqdn(:prod, location)}:8000" }
  end

  def to_loadbalancer_config(location)
    if @disable_http_lb_hack && @one_instance_in_lb
      fail('disable_http_lb_hack and one_instance_in_lb cannot be specified at the same time')
    end
    config = {}
    if respond_to?(:load_balanced_service?)
      config = loadbalancer_config(location)
      unless @sso_port.nil?
        if @disable_http_lb_hack
          config[vip_fqdn(:prod, location)]['type'] = 'sso_app'
        else
          config[vip_fqdn(:prod, location)]['type'] = 'http_and_sso_app'
        end
      end
    end
    if @one_instance_in_lb
      config[vip_fqdn(:prod, location)]['type'] = 'one_instance_in_lb_with_sorry_server'
    end
    config
  end
end