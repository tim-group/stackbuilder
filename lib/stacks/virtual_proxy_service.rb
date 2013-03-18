require 'stacks/namespace'
require 'stacks/machine_def_container'
require 'stacks/app_server'
require 'stacks/nat'
require 'uri'

class Stacks::ProxyVHost
  attr_reader :aliases
  attr_reader :vhost_fqdn
  attr_reader :redirects

  def initialize(vhost_fqdn, service, &block)
    @vhost_fqdn = vhost_fqdn
    @service = service
    @aliases = []
    @redirects = []
    self.instance_eval &block
  end

  def with_alias(alias_fqdn)
    @aliases << alias_fqdn
  end

  def with_redirect(redirect_fqdn)
    @redirects << redirect_fqdn
  end
end

class Stacks::VirtualProxyService < Stacks::VirtualService
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def initialize(name, &config_block)
    super(name, &config_block)
    @downstream_services = []
    @proxy_vhosts_lookup = {}
    @proxy_vhosts = []
    @config_block = config_block
    @port = 80
  end

  def bind_to(environment)
    @environment = environment
    @fabric = environment.options[:primary_site]
    @domain = "#{@fabric}.net.local"
    @instances.times do |i|
      index = sprintf("%03d",i+1)
      @definitions["#{name}-#{index}"] = server = Stacks::ProxyServer.new(self, index, &@config_block)
    end
    super(environment)
  end

  def vhost(service, options={}, &config_block)
    @proxy_vhosts << @proxy_vhosts_lookup[service] = Stacks::ProxyVHost.new(options[:server_name] || vip_front_fqdn, service, &config_block)
  end

  def downstream_services
    services = []

    vhost_map = @proxy_vhosts_lookup.values.group_by do |proxy_vhost|
      proxy_vhost.vhost_fqdn
    end

    duplicates = Hash[vhost_map.select do |key, values|
      values.size>1
    end]

    raise "duplicate keys found #{duplicates.keys.inspect}" unless duplicates.size==0

    environment.accept do |machine_def|
      if machine_def.kind_of? Stacks::VirtualAppService
        if @proxy_vhosts_lookup.include?(machine_def.name)
          vhost = @proxy_vhosts_lookup[machine_def.name]
          services << [vhost.vhost_fqdn, {
            'aliases' => vhost.aliases,
            'redirects' => vhost.redirects,
            'application' => machine_def.application,
            'proxy_pass_to' => "http://#{machine_def.vip_fqdn}:8000"
          }]
        end
      end
    end

    return services
  end
end
