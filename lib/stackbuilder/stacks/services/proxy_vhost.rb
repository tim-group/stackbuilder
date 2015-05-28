class Stacks::Services::ProxyVHost
  attr_accessor :aliases
  attr_accessor :cert
  attr_reader :properties
  attr_reader :proxy_pass_rules
  attr_reader :redirects
  attr_reader :service
  attr_reader :type
  attr_reader :environment

  def initialize(virtual_proxy_service, fqdn, service, environment, location, type = 'default', &block)
    @aliases = []
    @add_default_aliases = true
    @cert = 'wildcard_timgroup_com'
    @properties = {}
    @proxy_pass_rules = {}
    @redirects = []
    @service = service
    @type = type
    @fqdn = fqdn
    @environment = environment
    @virtual_proxy_service = virtual_proxy_service
    @location = location
    instance_eval(&block) if block
  end

  # XXX looks like this method is never used
  def with_redirect(redirect_fqdn)
    @redirects << redirect_fqdn
  end

  def add_pass_rule(path, config_hash)
    config_hash[:location] = :primary_site if config_hash[:location].nil?
    @proxy_pass_rules[path] = config_hash
    @virtual_proxy_service.depend_on config_hash[:service], config_hash[:environment], config_hash[:location]
  end

  def add_properties(properties)
    @properties.merge!(properties)
  end

  def aliases(location)
    aliases = Set.new
    if @add_default_aliases
      aliases << @virtual_proxy_service.vip_fqdn(:front, location)
      aliases << @virtual_proxy_service.vip_fqdn(:prod, location)
    end
    aliases.merge(@aliases)
    aliases.delete(fqdn(location))
    aliases.to_a.sort
  end

  def fqdn(location)
    if @fqdn.nil?
      @virtual_proxy_service.vip_fqdn(:front, location)
    else
      @fqdn
    end
  end

  def proxy_pass_rules(location)
    vhost_location = @virtual_proxy_service.override_vhost_location[@environment]
    vhost_location = location if vhost_location.nil?

    Hash[@proxy_pass_rules.map do |path, config_hash|
      service_environment = environment
      service_environment = config_hash[:environment] if config_hash.key?(:environment)
      service = @virtual_proxy_service.find_virtual_service(config_hash[:service], service_environment)
      [path, "http://#{service.vip_fqdn(:prod, vhost_location)}:8000"]
    end]
  end

  def to_proxy_config_hash(location)
    [fqdn(location), {
      'aliases'          => aliases(location),
      'redirects'        => redirects,
      'application'      => @virtual_proxy_service.find_virtual_service(service, environment).application,
      'proxy_pass_rules' => proxy_pass_rules(location),
      'type'             => type,
      'vhost_properties' => properties,
      'cert'             => cert
    }]
  end
end
