require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'stacks/proxy_vhost'
require 'uri'

module Stacks::VirtualProxyService
  attr_reader :cert
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def self.extended(object)
    object.configure
  end

  def configure
    @downstream_services = []
    @proxy_vhosts_lookup = {}
    @proxy_vhosts        = []
    @ports               = [80, 443]
    @cert                = 'wildcard_timgroup_com'
  end

  def vhost(service, fqdn = nil, &config_block)
    fqdn = vip_fqdn(:front) if !fqdn
    proxy_vhost = Stacks::ProxyVHost.new(fqdn, service, &config_block)

    if proxy_vhost.add_default_aliases == true
      proxy_vhost.aliases << vip_fqdn(:front) if fqdn != vip_fqdn(:front)
      proxy_vhost.aliases << vip_fqdn(:prod)
    end
    key = "#{fqdn}-#{name}-#{service}"
    @proxy_vhosts << @proxy_vhosts_lookup[key] = proxy_vhost
  end

  def find_virtual_service(service, environment_name = environment.name)
    find_environment(environment_name).accept do |machine_def|
      if machine_def.kind_of?(Stacks::AbstractVirtualService) && service.eql?(machine_def.name)
        return machine_def
      end
    end

    raise "Cannot find the service called #{service}"
  end

  def set_default_ssl_cert(cert_name)
    @cert = cert_name
  end

  def depends_on
    @proxy_vhosts_lookup.values.map do |vhost|
      [vhost.service, environment.name]
    end
  end

  def downstream_services
    vhost_map = @proxy_vhosts_lookup.values.group_by(&:vhost_fqdn)

    duplicates = Hash[vhost_map.select do |key, values|
      values.size > 1
    end]

    raise "duplicate keys found #{duplicates.keys.inspect}" unless duplicates.size == 0

    Hash[@proxy_vhosts_lookup.values.map do |vhost|
      # FIXME: the default proxy pass can't hand off to a service in a different environment
      # This is fine right now, but as soon as something like some proxy's in the shared environment
      # need to hand off to a service in another environment, we're stuffed until this is fixed
      primary_app = find_virtual_service(vhost.service)
      proxy_pass_rules = Hash[vhost.proxy_pass_rules.map do |path, config_hash|
        if config_hash.key? :environment
          [path, "http://#{find_virtual_service(config_hash[:service], config_hash[:environment]).vip_fqdn(:prod)}:8000"]
        else
          [path, "http://#{find_virtual_service(config_hash[:service]).vip_fqdn(:prod)}:8000"]
        end
      end]

      proxy_pass_rules['/'] = "http://#{primary_app.vip_fqdn(:prod)}:8000"

      [vhost.vhost_fqdn, {
        'aliases' => vhost.aliases,
        'redirects' => vhost.redirects,
        'application' => primary_app.application,
        'proxy_pass_rules' => proxy_pass_rules,
        'type'  => vhost.type,
        'vhost_properties' => vhost.properties,
        'cert' => vhost.cert
      }]
    end]
  end

  def to_loadbalancer_config
    grouped_realservers = realservers.group_by do |realserver|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, realservers|
      realserver_fqdns = realservers.map(&:prod_fqdn).sort
      [group, realserver_fqdns]
    end]

    enc = {
      'type' => 'proxy',
      'ports' => @ports,
      'realservers' => realservers
    }

    unless @persistent_ports.empty?
      persistence = { 'persistent_ports' => @persistent_ports }
      enc = enc.merge(persistence)
    end

    {
      vip_fqdn(:prod) => enc
    }
  end
end
