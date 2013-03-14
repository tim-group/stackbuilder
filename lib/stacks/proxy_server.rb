require 'stacks/namespace'

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

class Stacks::ProxyServer < Stacks::MachineDef
  attr_reader :virtual_service
  attr_accessor :group

  def initialize(virtual_service, index, &config_block)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
    @downstream_services = []
    @proxy_vhosts_lookup = {}
    @proxy_vhosts = []
    @config_block = config_block
  end

  def bind_to(environment)
    super(environment)
    self.instance_eval(&@config_block)
  end

  def vhost(service, &config_block)
    @proxy_vhosts << @proxy_vhosts_lookup[service] = Stacks::ProxyVHost.new(virtual_service.vip_front_fqdn, service, &config_block)
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
      if machine_def.kind_of? Stacks::VirtualService
        if @proxy_vhosts_lookup.include?(machine_def.name)
          vhost = @proxy_vhosts_lookup[machine_def.name]
          services << [virtual_service.vip_front_fqdn, {
            'aliases' => vhost.aliases,
            'redirects' => vhost.redirects,
            'application' => "#{machine_def.name}",
            'proxy_pass_to' => "http://#{machine_def.vip_fqdn}:8000"
          }]
        end
      end
    end

    return services
  end

  def to_enc
    service_resources = Hash[downstream_services()]
    {'role::proxyserver' => {
        'prod_vip_fqdn' => self.virtual_service.vip_fqdn,
        'vhosts'  => service_resources
      }
    }
  end
end
