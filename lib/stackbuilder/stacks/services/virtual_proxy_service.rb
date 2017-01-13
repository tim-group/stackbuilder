require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/services/proxy_vhost'

module Stacks::Services::VirtualProxyService
  attr_reader :cert
  attr_reader :proxy_vhosts
  attr_reader :is_use_deployapp_enabled
  attr_reader :use_deployapp
  attr_accessor :override_vhost_location

  def self.extended(object)
    object.configure
  end

  def configure
    @proxy_vhosts            = []
    @ports                   = [80, 443]
    @cert                    = 'wildcard_timgroup_com'
    @override_vhost_location = {}
    @vhost_for_lb_healthcheck_override_hack = nil
    @enable_use_for_lb_healthcheck = false
    @use_deployapp = true
    @is_use_deployapp_enabled = false
  end

  def vhost(service, fqdn = nil, service_env_name = nil, service_location = :primary_site, &config_block)
    service_env_name = environment.name if service_env_name.nil?
    vhost = Stacks::Services::ProxyVHost.new(self, fqdn, service, service_env_name, service_location, &config_block)
    vhost.add_pass_rule('/', :service => service, :environment => service_env_name, :location => service_location)
    @proxy_vhosts << vhost
  end

  def find_virtual_service(service, environment_name = environment.name)
    @environment.find_environment(environment_name).accept do |machine_def|
      if machine_def.is_a?(Stacks::Services::AbstractVirtualService) && service.eql?(machine_def.name)
        return machine_def
      end
    end

    fail "Cannot find the service called #{service} in #{environment_name}"
  end

  def downstream_services(proxy_location)
    Hash[@proxy_vhosts.map do |vhost|
      vhost.to_proxy_config_hash(proxy_location, environment)
    end]
  end

  def to_loadbalancer_config(location, fabric)
    grouped_realservers = realservers(location).group_by do |_|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, grealservers|
      grealserver_fqdns = grealservers.map(&:prod_fqdn).sort
      [group, grealserver_fqdns]
    end]

    type = @is_use_deployapp_enabled && @use_deployapp ? 'proxy_with_deployapp' : 'proxy'

    enc = {
      'env' => environment.name,
      'app' => 'apache2',
      'type' => type,
      'ports' => @ports,
      'realservers' => realservers
    }

    enc['vhost_for_healthcheck'] = vhost_for_healthcheck(fabric) if @enable_use_for_lb_healthcheck

    unless @persistent_ports.empty?
      persistence = { 'persistent_ports' => @persistent_ports }
      enc = enc.merge(persistence)
    end

    {
      vip_fqdn(:prod, fabric) => enc
    }
  end

  def vhost_for_lb_healthcheck_override_hack(vhost_name)
    fail("vhost_for_lb_healthcheck_override_hack is already set to #{@vhost_for_lb_healthcheck_override_hack} " \
         "for service '#{name}' in environment '#{environment.name}'") unless @vhost_for_lb_healthcheck_override_hack.nil?
    @vhost_for_lb_healthcheck_override_hack = vhost_name
  end

  def enable_use_for_lb_healthcheck
    @enable_use_for_lb_healthcheck = true
  end

  def enable_use_deployapp
    @is_use_deployapp_enabled = true
  end

  def disable_using_deployapp
    @use_deployapp = false
  end

  private

  def vhost_for_healthcheck(fabric)
    return @vhost_for_lb_healthcheck_override_hack unless @vhost_for_lb_healthcheck_override_hack.nil?
    vhsts = @proxy_vhosts.select(&:use_for_lb_healthcheck?)
    case vhsts.length
    when 0
      fail("No vhosts of service '#{name}' in environment '#{environment.name}' are configured to be used for load balancer healthchecks")
    when 1
      vhsts.first.fqdn(fabric)
    else
      fail("More than one vhost of service '#{name}' in environment '#{environment.name}' are configured to be used for " \
           "load balancer healthchecks: #{vhsts.map { |vhst| vhst.fqdn(fabric) }.join(',')}")
    end
  end
end
