class Stacks::Services::ProxyVHost
  attr_accessor :aliases
  attr_accessor :cert
  attr_accessor :monitor_vhost
  attr_accessor :log_to_sylog
  attr_reader :proxy_pass_rules
  attr_reader :service
  attr_reader :environment

  def initialize(virtual_proxy_service, fqdn, service, environment, location, &block)
    @aliases = []
    @add_default_aliases = true
    @cert = virtual_proxy_service.cert
    @proxy_pass_rules = {}
    @service = service
    @fqdn = fqdn
    @environment = environment
    @virtual_proxy_service = virtual_proxy_service
    @location = location
    @ensure = 'present'
    @monitor_vhost = true
    @use_for_lb_healthcheck = false
    @log_to_syslog = false
    instance_eval(&block) if block
  end

  def add_pass_rule(path, config_hash)
    config_hash[:environment] = @environment if config_hash[:environment].nil?
    config_hash[:location] = :primary_site if config_hash[:location].nil?
    @proxy_pass_rules[path] = config_hash
    @virtual_proxy_service.depend_on config_hash[:service], config_hash[:environment]
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

  def proxy_pass_rules(location, environments, machine_index)
    vhost_location = @virtual_proxy_service.override_vhost_location[@environment]
    vhost_location = location if vhost_location.nil?

    Hash[@proxy_pass_rules.map do |path, config_hash|
      service_environment = environment
      service_environment = config_hash[:environment] if config_hash.key?(:environment)
      service = @virtual_proxy_service.find_virtual_service(config_hash[:service], machine_index, service_environment)
      port = service.kubernetes ? 80 : 8000
      fabric = environments[service_environment].options[vhost_location]
      [path, "http://#{service.vip_fqdn(:prod, fabric)}:#{port}#{config_hash[:path]}"]
    end]
  end

  def to_proxy_config_hash(location, environment, machine_index)
    envs = environment.all_environments
    fabric = envs[@environment].options[location]
    config = {
      'ensure'                  => @ensure,
      'aliases'                 => aliases(fabric),
      'application'             => @virtual_proxy_service.find_virtual_service(service, machine_index, @environment).application,
      'proxy_pass_rules'        => proxy_pass_rules(location, envs, machine_index),
      'cert'                    => cert,
      'monitor_vhost'           => @monitor_vhost,
      'log_to_syslog'           => @log_to_syslog
    }
    config['used_for_lb_healthcheck'] = use_for_lb_healthcheck?
    [fqdn(fabric), config]
  end

  def absent
    @ensure = 'absent'
  end

  def use_for_lb_healthcheck
    @use_for_lb_healthcheck = true
  end

  def use_for_lb_healthcheck?
    @use_for_lb_healthcheck
  end
end
