require 'stackbuilder/stacks/kubernetes/namespace'
require 'stackbuilder/stacks/maintainers'
require 'erb'

module Stacks::Services::BaseK8sApp
  include Stacks::Kubernetes::ResourceSetApp
  include Stacks::Maintainers

  attr_accessor :ports
  attr_accessor :ephemeral_storage_size
  attr_accessor :cpu_request
  attr_accessor :cpu_limit
  attr_accessor :memory_limit

  attr_accessor :command
  attr_accessor :args
  attr_accessor :capabilities
  attr_accessor :readiness

  attr_accessor :appconfig

  attr_accessor :alerts_channel
  attr_accessor :startup_alert_threshold
  attr_accessor :monitor_tucker
  attr_accessor :monitor_readiness_probe
  attr_accessor :page_on_critical

  attr_accessor :application
  attr_accessor :description
  attr_accessor :maintainers

  def self.extended(object)
    object.configure
  end

  def configure
    @ports = {}
    @ephemeral_storage_size = nil
    @maintainers = []
    @cpu_request = false
    @cpu_limit = false
    @monitor_readiness_probe = false
    @monitor_tucker = false
    @page_on_critical = false
    @artifact_from_nexus = false
    @memory_limit = '64Mi'
    @command = nil
    @args = nil
    @capabilities = nil
    @readiness = nil
    @appconfig = nil
    @allow_from_aws_alb = false
  end

  def to_k8s(app_deployer, dns_resolver, hiera_provider)
    assert_k8s_requirements

    instances = if @instances.is_a?(Hash)
                  @instances
                else
                  { @environment.sites.first => @instances }
                end

    instances.map do |site, replicas|
      app_name = application.downcase
      group = @groups.first

      begin
        app_version = app_deployer.query_cmdb_for(:application => application,
                                                  :environment => @environment.name,
                                                  :group => group)[:target_version]
      rescue
        raise("Version not found in cmdb for application: '#{application}', group: '#{group}' in environment: '#{environment.name}'")
      end

      domain = "mgmt.#{environment.domain(site)}"

      hiera_scope = {
        'domain' => domain,
        'hostname' => kubernetes ? identity : children.first.hostname,
        'application' => application,
        'stackname' => @stack.name,
        'logicalenv' => @environment.name,
        'group' => group,
        'site' => site
      }

      fake_machine_instance = Struct.new(:index).new(0)
      erb_vars = {
        'dependencies' => dependency_config(site, fake_machine_instance),
        'credentials_selector' => hiera_provider.lookup(hiera_scope, 'stacks/application_credentials_selector', nil)
      }.merge(hiera_scope)

      config, used_secrets = generate_app_config(erb_vars, hiera_provider)

      output = super app_deployer, dns_resolver, hiera_provider, service_adjusted_labels
      output += app_generate_resources(app_deployer, dns_resolver, hiera_provider, hiera_scope, app_name, app_version, replicas, used_secrets, site, \
                                       standard_labels, service_adjusted_labels, k8s_app_resources_name, config)

      Stacks::KubernetesResourceBundle.new(site, @environment.name, service_adjusted_labels, output, used_secrets, hiera_scope, k8s_app_resources_name)
    end
  end

  def prod_fqdn(fabric)
    if respond_to? :vip_fqdn
      vip_fqdn(:prod, fabric)
    else
      children.first.prod_fqdn
    end
  end

  def endpoints(_dependent_service, fabric)
    @ports.keys.map do |port_name|
      {
        :port => @ports[port_name]['port'],
        :fqdns => [prod_fqdn(fabric)]
      }
    end
  end

  def standard_labels
    {
      'app.kubernetes.io/managed-by' => 'stacks',
      'stack' => @stack.name,
      'machineset' => name,
      'group' => groups.first,
      'app.kubernetes.io/instance' => groups.first,
      'app.kubernetes.io/part-of' => @short_name
    }
  end

  def service_adjusted_labels
    standard_labels.merge('app.kubernetes.io/component' => @custom_service_name)
  end

  def k8s_app_resources_name
    group = @groups.first
    "#{name}-#{group}-#{k8s_type}"
  end

  private

  def assert_k8s_requirements
    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' doesn't define @ports but is depended on by another service") \
      if @ports.empty? && non_k8s_dependencies_exist?

    unknown_ports = @ports.keys - %w(app metrics)
    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' defines port(s) named <#{unknown_ports.join(', ')}>." \
      " Only 'app' and 'metrics' are currently supported") \
      if !unknown_ports.empty?

    ports_without_protocol = @ports.select { |_, v| !v.key?('protocol') }
    fail("#{custom_service_name} '#{name}' in '#{environment.name}' does not define a protocol for port(s) " \
      "<#{ports_without_protocol.keys.join(',')}>") if !ports_without_protocol.empty?

    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' requires maintainers (set self.maintainers)") if @maintainers.empty?
    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' requires description (set self.description)") if @description.nil?
    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' requires application") if application.nil?
    fail("#{custom_service_name} '#{name}' in '#{@environment.name} to_k8s doesn\'t know how to deal with multiple groups yet") if @groups.size > 1
    fail("#{custom_service_name} '#{name}' in '#{@environment.name} to_k8s doesn\'t know how to deal with @enable_secondary_site yet") \
      if @enable_secondary_site
    fail "#{custom_service_name} '#{name}' in '#{@environment.name}', you must specify a cpu_request if specifying a cpu_limit" \
      if @cpu_limit && !@cpu_request
  end

  def k8s_type
    "app"
  end

  def startup_alert_threshold_seconds
    fail "You must specify a maximum startup time threshold in a kubernetes app service" if @startup_alert_threshold.nil?

    t = @startup_alert_threshold.match(/^(\d+)(s|m|h)$/)
    case t.captures[1].upcase
    when 'S'
      t.captures[0].to_i
    when 'M'
      t.captures[0].to_i * 60
    when 'H'
      t.captures[0].to_i * 60 * 60
    end
  end

  def generate_app_config(erb_vars, hiera_provider)
    template = @pre_appconfig_template.nil? ? '' : @pre_appconfig_template
    template += @appconfig if @appconfig
    template += @post_appconfig_template.nil? ? '' : @pre_appconfig_template # TODO: waz - what is this?

    erb = ConfigERB.new(template, erb_vars, hiera_provider)
    contents = erb.render unless template.empty?

    [contents, erb.used_secrets]
  end
end
