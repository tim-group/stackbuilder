require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::AppServer < Stacks::MachineDef
  attr_reader :environment
  attr_reader :location
  attr_reader :ram
  attr_reader :storage
  attr_accessor :group
  attr_accessor :launch_config

  def initialize(virtual_service, base_hostname, environment, site, role)
    super(virtual_service, base_hostname, environment, site, role)
    @allowed_hosts = []
    @launch_config = {}
    @enc_hacks = []
  end

  def allow_host(source_host_or_network)
    @allowed_hosts << source_host_or_network
    @allowed_hosts.uniq!
  end

  def dependency_config_sftp_servers_only(fabric)
    @virtual_service.dependency_config(fabric, self).reject { |key, _value| key != 'sftp_servers' }
  end

  def dependency_config_excluding_sftp_servers(fabric)
    @virtual_service.dependency_config(fabric, self).reject! { |key, _value| key == 'sftp_servers' }
  end

  def normalize_storage
    root_size_cur = @storage['/'.to_sym][:size].chomp('G').to_i
    root_size_min = @ram.to_i / 524288 + 2

    if root_size_cur < root_size_min
      modify_storage('/' => { :size => root_size_min.to_s.concat('G') })
    end
    nil
  end

  def enc_hack(&block)
    @enc_hacks << block
  end

  def to_enc
    enc = super
    enc['role::http_app'] = {
      'application'                       => @virtual_service.application,
      'group'                             => group,
      'cluster'                           => availability_group,
      'environment'                       => environment.name,
      'dependencies'                      => @virtual_service.dependency_config(fabric, self),
      'application_dependant_instances'   => @virtual_service.dependant_instance_fqdns(location, [@environment.primary_network], true, true),
      'participation_dependant_instances' => @virtual_service.dependant_load_balancer_fqdns(location),
      'port'                              => '8000',
      'use_docker'                        => @virtual_service.use_docker
    }

    enc_dependant_kubernetes_things enc

    enc['role::http_app']['jvm_args'] = @virtual_service.jvm_args unless @virtual_service.jvm_args.nil?
    enc['role::http_app']['sso_port'] = @virtual_service.sso_port unless @virtual_service.sso_port.nil?
    enc['role::http_app']['ajp_port'] = @virtual_service.ajp_port unless @virtual_service.ajp_port.nil?

    allowed_hosts = @allowed_hosts
    allowed_hosts += @virtual_service.allowed_hosts if @virtual_service.respond_to? :allowed_hosts
    enc['role::http_app']['allowed_hosts'] = allowed_hosts.uniq.sort unless allowed_hosts.empty?

    if @virtual_service.respond_to? :vip_fqdn
      enc['role::http_app']['vip_fqdn'] = @virtual_service.vip_fqdn(:prod, @fabric)
    end

    # FIXME: It is less than ideal having to use the same dependency mechanism for
    # ideas position exports as the app server itself.
    # The hash returned by dependency_config leaks into the role::http_app as
    # 'dependencies', we therefore strip these out to avoid complications.
    # Likewise we strip an non-sftp servers and see them to idea_positions_exports::appserver
    #
    if @virtual_service.idea_positions_exports
      enc['role::http_app']['dependencies'] = dependency_config_excluding_sftp_servers(fabric)
      enc.merge!('idea_positions_exports::appserver' => dependency_config_sftp_servers_only(fabric))
    end

    enc_ehcache(enc)
    enc_tomcat_session_replication(enc)

    unless @launch_config.empty?
      enc['role::http_app']['launch_config'] = @launch_config
    end

    @enc_hacks.inject(enc) do |_enc, hack|
      hack.call(enc)
    end
  end

  private

  def enc_dependant_kubernetes_things(enc)
    dependant_app_services = @virtual_service.virtual_services_that_depend_on_me.select do |machine_set|
      machine_set.is_a? Stacks::Services::AppService
    end

    return unless dependant_app_services.any?(&:kubernetes)

    k8s_dependant_app_fabrics = dependant_app_services.select(&:kubernetes).map { |vs| vs.environment.options[:primary_site] }

    my_service_is_in_a_single_site = @virtual_service.instances.is_a?(Numeric) ||
                                     (@virtual_service.instances.is_a?(Hash) && @virtual_service.instances.size == 1)

    k8s_clusters = k8s_dependant_app_fabrics.reject do |s|
      s != site unless my_service_is_in_a_single_site
    end.uniq

    enc['role::http_app']['allow_kubernetes_clusters'] = k8s_clusters
  end

  def enc_ehcache(enc)
    return unless @virtual_service.ehcache
    peers = @virtual_service.children.map do |child|
      child.qualified_hostname(:prod)
    end

    peers.delete qualified_hostname(:prod)

    return if peers == []
    enc['role::http_app']['dependencies']['cache.enabled'] = "true"
    enc['role::http_app']['dependencies']['cache.peers'] = "[\"#{peers.join(',')}\"]"
    enc['role::http_app']['dependencies']['cache.registryPort'] = "49000"
    enc['role::http_app']['dependencies']['cache.remoteObjectPort'] = "49010"
  end

  def enc_tomcat_session_replication(enc)
    return if @virtual_service.nil?
    return unless @virtual_service.tomcat_session_replication == true
    peers = @virtual_service.children.map do |child|
      child.qualified_hostname(:prod)
    end

    peers.delete qualified_hostname(:prod)

    enc['role::http_app']['dependencies']['cluster.enabled'] = 'true'
    enc['role::http_app']['dependencies']['cluster.domain'] = availability_group
    enc['role::http_app']['dependencies']['cluster.receiver.address'] = qualified_hostname(:prod)
    enc['role::http_app']['dependencies']['cluster.members'] = "#{peers.sort.join(',')}"
  end
end
