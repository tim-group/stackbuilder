require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'stacks/proxy_vhost'
require 'uri'

class Stacks::VirtualProxyService < Stacks::VirtualService
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def initialize(name, &config_block)
    super(name, &config_block)
    @downstream_services = []
    @proxy_vhosts_lookup = {}
    @proxy_vhosts = []
    @config_block = config_block
    @ports = [80, 443]
  end

  def bind_to(environment)
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = Stacks::ProxyServer.new(self, index, &@config_block)
    end
    super(environment)
  end

  def vhost(service, options={}, &config_block)
    key = "#{self.name}.vhost.#{service}.server_name"
    if (environment.options.has_key?(key))
      proxy_vhost = Stacks::ProxyVHost.new(environment.options[key] || vip_front_fqdn, service, &config_block)
      proxy_vhost.with_alias(vip_front_fqdn)
    else
      proxy_vhost = Stacks::ProxyVHost.new(vip_front_fqdn, service, &config_block)
    end
    proxy_vhost.with_alias(vip_fqdn)
    @proxy_vhosts << @proxy_vhosts_lookup[service] = proxy_vhost
  end

  def find_virtual_service(service)
    environment.accept do |machine_def|
      if machine_def.kind_of? Stacks::VirtualAppService and service.eql? machine_def.name
        return machine_def
      end
    end

    raise "Cannot find the service called "#{service}"
  end

  def downstream_services
    vhost_map = @proxy_vhosts_lookup.values.group_by do |proxy_vhost|
      proxy_vhost.vhost_fqdn
    end

    duplicates = Hash[vhost_map.select do |key, values|
      values.size>1
    end]

    raise "duplicate keys found #{duplicates.keys.inspect}" unless duplicates.size==0

    return Hash[@proxy_vhosts_lookup.values.map do |vhost|
      primary_app = find_virtual_service(vhost.service)

      proxy_pass_rules = Hash[vhost.proxy_pass_rules.map do |path, service|
        [path, "http://#{find_virtual_service(service).vip_fqdn}:8000"]
      end]

      proxy_pass_rules['/'] = "http://#{primary_app.vip_fqdn}:8000"

      [vhost.vhost_fqdn, {
        'aliases' => vhost.aliases,
        'redirects' => vhost.redirects,
        'application' => primary_app.application,
        'proxy_pass_rules' => proxy_pass_rules
      }]
    end]

  end

  def to_loadbalancer_config
    grouped_realservers = self.realservers.group_by do |realserver|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, realservers|
      realserver_fqdns = realservers.map do |realserver|
        realserver.prod_fqdn
      end.sort
      [group, realserver_fqdns]
    end]

    [self.vip_fqdn, {
      'type' => 'proxy',
      'realservers' => realservers
    }]
  end
end
