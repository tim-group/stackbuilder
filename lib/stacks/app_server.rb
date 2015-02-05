require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::AppServer < Stacks::MachineDef

  attr_reader :environment, :virtual_service
  attr_accessor :group
  attr_accessor :launch_config

  def initialize(virtual_service, index, &block)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
    @allowed_hosts = []
    @included_classes = {}
    @launch_config = {}
  end

  def bind_to(environment)
    super(environment)
  end

  def vip_fqdn(net)
    return @virtual_service.vip_fqdn(net)
  end

  def allow_host(source_host_or_network)
    @allowed_hosts << source_host_or_network
    @allowed_hosts.uniq!
  end

  def include_class(class_name, class_hash = {})
    @included_classes[class_name] = class_hash
  end

  public
  def to_enc()
    enc = super
    enc['role::http_app'] = {
      'application' => virtual_service.application,
      'group' => group,
      'environment' => environment.name,
      'dependencies' => @virtual_service.dependency_config,
      'dependant_instances' => @virtual_service.dependant_machine_def_fqdns,
      'port' => '8000',
    }

    enc['role::http_app']['jvm_args'] = @virtual_service.jvm_args unless @virtual_service.jvm_args.nil?
    enc['role::http_app']['sso_port'] = @virtual_service.sso_port unless @virtual_service.sso_port.nil?
    enc['role::http_app']['ajp_port'] = @virtual_service.ajp_port unless @virtual_service.ajp_port.nil?

    allowed_hosts = @allowed_hosts
    allowed_hosts = allowed_hosts + @virtual_service.allowed_hosts if @virtual_service.respond_to? :allowed_hosts
    enc['role::http_app']['allowed_hosts'] = allowed_hosts.uniq.sort unless allowed_hosts.empty?

    enc.merge! @included_classes
    enc.merge! @virtual_service.included_classes if @virtual_service.respond_to? :included_classes

    if @virtual_service.respond_to? :vip_fqdn
      enc['role::http_app']['vip_fqdn'] = @virtual_service.vip_fqdn(:prod)
    end

    if @virtual_service.ehcache
      peers = @virtual_service.children.map do |child|
        child.qualified_hostname(:prod)
      end

      peers.delete self.qualified_hostname(:prod)

      unless peers == []
        enc['role::http_app']['dependencies']['cache.enabled'] = "true"
        enc['role::http_app']['dependencies']['cache.peers'] = "[\"#{peers.join(',')}\"]"
        enc['role::http_app']['dependencies']['cache.registryPort'] = "49000"
        enc['role::http_app']['dependencies']['cache.remoteObjectPort'] = "49010"
      end
    end

    unless @launch_config.empty?
      enc['role::http_app']['launch_config'] = @launch_config
    end

    enc
  end
end
