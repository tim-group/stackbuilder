require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::Services::AppServer < Stacks::MachineDef
  attr_reader :environment
  attr_reader :location
  attr_accessor :group
  attr_accessor :launch_config

  def initialize(virtual_service, index, networks = [:mgmt, :prod], location = :primary_site)
    super(virtual_service.name + "-" + index, networks, location)
    @virtual_service = virtual_service
    @allowed_hosts = []
    @launch_config = {}
    modify_storage('/' => { :size => '5G' })
  end

  def bind_to(environment)
    super(environment)
  end

  def allow_host(source_host_or_network)
    @allowed_hosts << source_host_or_network
    @allowed_hosts.uniq!
  end

  def dependency_config_sftp_servers_only(location)
    @virtual_service.dependency_config(location).reject { |key, _value| key != 'sftp_servers' }
  end

  def dependency_config_excluding_sftp_servers(location)
    @virtual_service.dependency_config(location).reject! { |key, _value| key == 'sftp_servers' }
  end

  def to_enc
    enc = super
    enc['role::http_app'] = {
      'application'                       => @virtual_service.application,
      'group'                             => group,
      'cluster'                           => availability_group,
      'environment'                       => environment.name,
      'dependencies'                      => @virtual_service.dependency_config(location),
      'application_dependant_instances'   => @virtual_service.dependant_instance_fqdns(location),
      'participation_dependant_instances' => @virtual_service.dependant_load_balancer_fqdns(location),
      'port'                              => '8000'
    }

    enc['role::http_app']['jvm_args'] = @virtual_service.jvm_args unless @virtual_service.jvm_args.nil?
    enc['role::http_app']['sso_port'] = @virtual_service.sso_port unless @virtual_service.sso_port.nil?
    enc['role::http_app']['ajp_port'] = @virtual_service.ajp_port unless @virtual_service.ajp_port.nil?

    allowed_hosts = @allowed_hosts
    allowed_hosts += @virtual_service.allowed_hosts if @virtual_service.respond_to? :allowed_hosts
    enc['role::http_app']['allowed_hosts'] = allowed_hosts.uniq.sort unless allowed_hosts.empty?

    if @virtual_service.respond_to? :vip_fqdn
      enc['role::http_app']['vip_fqdn'] = @virtual_service.vip_fqdn(:prod, @location)
    end

    # FIXME: It is less than ideal having to use the same dependency mechanism for
    # ideas position exports as the app server itself.
    # The hash returned by dependency_config leaks into the role::http_app as
    # 'dependencies', we therefore strip these out to avoid complications.
    # Likewise we strip an non-sftp servers and see them to idea_positions_exports::appserver
    #
    if @virtual_service.idea_positions_exports
      enc['role::http_app']['dependencies'] = dependency_config_excluding_sftp_servers(location)
      enc.merge!('idea_positions_exports::appserver' => dependency_config_sftp_servers_only(location))
    end

    enc_ehcache(enc)
    enc_tomcat_session_replication(enc)

    unless @launch_config.empty?
      enc['role::http_app']['launch_config'] = @launch_config
    end

    enc
  end

  private

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
