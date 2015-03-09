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

  def vhost(service, vhost_properties = {}, &config_block)
    key = "#{name}.vhost.#{service}.server_name"
    _vhost(key, vip_fqdn(:front), vip_fqdn(:prod), service, 'default', vhost_properties, &config_block)
  end

  def vhost2(fqdn, service, &config_block)
    proxy_vhost = Stacks::ProxyVHost.new(fqdn, service, &config_block)
    if proxy_vhost.add_default_aliases == true
      proxy_vhost.aliases << vip_fqdn(:front)
      proxy_vhost.aliases << vip_fqdn(:prod)
    end
    key = "#{fqdn}-#{name}-#{service}"
    @proxy_vhosts << @proxy_vhosts_lookup[key] = proxy_vhost
  end

  def sso_vip_front_fqdn
    "#{environment.name}-#{name}-sso-vip.front.#{@domain}"
  end

  def sso_vip_fqdn
    "#{environment.name}-#{name}-sso-vip.#{@domain}"
  end

  def sso_vhost(service, vhost_properties = {}, &config_block)
    key = "#{name}.vhost.#{service}-sso.server_name"
    _vhost(key, sso_vip_front_fqdn, sso_vip_fqdn, service, 'sso', vhost_properties, &config_block)
  end

  def _vhost(key, default_vhost_fqdn, alias_fqdn, service, type, vhost_properties = {}, &config_block)
    if environment.options.key?(key)
      proxy_vhost = Stacks::ProxyVHost.new(environment.options[key], service, type, &config_block)
      proxy_vhost.with_alias(default_vhost_fqdn)
    else
      proxy_vhost = Stacks::ProxyVHost.new(default_vhost_fqdn, service, type, &config_block)
    end
    proxy_vhost.with_alias(alias_fqdn)
    proxy_vhost.vhost_properties(vhost_properties)
    @proxy_vhosts << @proxy_vhosts_lookup[key] = proxy_vhost
  end

  def find_virtual_service(service)
    environment.accept do |machine_def|
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
      primary_app = find_virtual_service(vhost.service)
      proxy_pass_rules = Hash[vhost.proxy_pass_rules.map do |path, service|
        [path, "http://#{find_virtual_service(service).vip_fqdn(:prod)}:8000"]
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
