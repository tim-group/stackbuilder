class Stacks::Services::ProxyVHost
  attr_accessor :aliases
  attr_accessor :cert
  attr_accessor :monitor_vhost
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
    @ensure = 'present'
    @monitor_vhost = true
    instance_eval(&block) if block
  end

  def with_redirect(redirect_fqdn)
    @redirects << redirect_fqdn
  end

  def add_pass_rule(path, config_hash)
    config_hash[:environment] = @environment if config_hash[:environment].nil?
    config_hash[:location] = :primary_site if config_hash[:location].nil?
    @proxy_pass_rules[path] = config_hash
    @virtual_proxy_service.depend_on config_hash[:service], config_hash[:environment]
  end

  def add_properties(properties)
    @properties.merge!(properties)
  end

  def aliases(fabric)
    aliases = Set.new
    if @add_default_aliases
      aliases << @virtual_proxy_service.vip_fqdn(:front, fabric)
      aliases << @virtual_proxy_service.vip_fqdn(:prod, fabric)
    end
    aliases.merge(@aliases)
    aliases.delete(fqdn(fabric))
    aliases.to_a.sort
  end

  def fqdn(fabric)
    if @fqdn.nil?
      @virtual_proxy_service.vip_fqdn(:front, fabric)
    else
      @fqdn
    end
  end

  def proxy_pass_rules(location, environments)
    vhost_location = @virtual_proxy_service.override_vhost_location[@environment]
    vhost_location = location if vhost_location.nil?

    Hash[@proxy_pass_rules.map do |path, config_hash|
      service_environment = environment
      service_environment = config_hash[:environment] if config_hash.key?(:environment)
      service = @virtual_proxy_service.find_virtual_service(config_hash[:service], service_environment)
      fabric = environments[service_environment].options[vhost_location]
      [path, "http://#{service.vip_fqdn(:prod, fabric)}:8000"]
    end]
  end

  def to_proxy_config_hash(location, environment)
    envs = environment.all_environments
    fabric = envs[@environment].options[location]
    [fqdn(fabric), {
      'ensure'           => @ensure,
      'aliases'          => aliases(fabric),
      'redirects'        => redirects,
      'application'      => @virtual_proxy_service.find_virtual_service(service, @environment).application,
      'proxy_pass_rules' => proxy_pass_rules(location, envs),
      'type'             => type,
      'vhost_properties' => properties,
      'cert'             => cert,
      'monitor_vhost'    => @monitor_vhost
    }]
  end

  def absent
    @ensure = 'absent'
  end
end
