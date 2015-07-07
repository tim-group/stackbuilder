require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/services/proxy_vhost'

module Stacks::Services::VirtualProxyService
  attr_reader :cert
  attr_reader :proxy_vhosts
  attr_accessor :override_vhost_location

  def self.extended(object)
    object.configure
  end

  def configure
    @proxy_vhosts            = []
    @ports                   = [80, 443]
    @cert                    = 'wildcard_timgroup_com'
    @override_vhost_location = {}
  end

  def vhost(service, fqdn = nil, service_env_name = nil, service_location = :primary_site, &config_block)
    service_env_name = environment.name if service_env_name.nil?
    vhost = Stacks::Services::ProxyVHost.new(self, fqdn, service, service_env_name, service_location, &config_block)
    vhost.add_pass_rule('/', :service => service, :environment => service_env_name, :location => service_location)
    @proxy_vhosts << vhost
  end

  def find_virtual_service(service, environment_name = environment.name)
    find_environment(environment_name).accept do |machine_def|
      if machine_def.is_a?(Stacks::Services::AbstractVirtualService) && service.eql?(machine_def.name)
        return machine_def
      end
    end

    fail "Cannot find the service called #{service} in #{environment_name}"
  end

  def downstream_services(proxy_location)
    Hash[@proxy_vhosts.map do |vhost|
      vhost.to_proxy_config_hash(proxy_location)
    end]
  end

  def to_loadbalancer_config(location)
    grouped_realservers = realservers(location).group_by do |_|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, grealservers|
      grealserver_fqdns = grealservers.map(&:prod_fqdn).sort
      [group, grealserver_fqdns]
    end]

    enc = {
      'type' => 'proxy',
      'ports' => @ports,
      'realservers' => realservers,
    }

    unless @persistent_ports.empty?
      persistence = { 'persistent_ports' => @persistent_ports }
      enc = enc.merge(persistence)
    end

    {
      vip_fqdn(:prod, location) => enc,
    }
  end
end
