require 'stackbuilder/stacks/kubernetes/namespace'
require 'stackbuilder/stacks/maintainers'

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

  attr_accessor :alerts_channel
  attr_accessor :startup_alert_threshold
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
    @monitor_readiness_probe = true
    @page_on_critical = false
    @artifact_from_nexus = false
    @memory_limit = '64Mi'
    @command = nil
    @args = nil
    @capabilities = nil
    @readiness = nil
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

      standard_labels = {
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => @stack.name,
        'machineset' => name,
        'group' => group,
        'app.kubernetes.io/instance' => group,
        'app.kubernetes.io/part-of' => @short_name
      }

      app_service_labels = standard_labels.merge('app.kubernetes.io/component' => 'app_service')

      config, used_secrets = generate_app_config(erb_vars, hiera_provider)

      output = super app_deployer, dns_resolver, hiera_provider, app_service_labels
      output += app_generate_resources(app_deployer, dns_resolver, hiera_provider, hiera_scope, app_name, app_version, replicas, used_secrets, site, \
                                       standard_labels, app_service_labels, k8s_app_resources_name, config)

      Stacks::KubernetesResourceBundle.new(site, @environment.name, app_service_labels, output, used_secrets, hiera_scope, k8s_app_resources_name)
    end
  end

  private

  # FIXME: base_k8s_app as a default is wrong, it should be the name of the method in custom_services.rb
  def assert_k8s_requirements(custom_service_name = 'base_k8s_app')
    # FIXME: There must be a better way to get the name of the last module that extended machineset rather than have to pass it in here?
    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' defines ports named both 'app' and 'http'. This is not possible at the moment " \
      "because in some places 'app' is fudged to be 'http' to avoid changing lots of things in one go.") \
      if @ports.keys.select { |port_name| %w(app http).include? port_name }.uniq.length > 1
    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' requires maintainers (set self.maintainers)") if @maintainers.empty?
    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' requires description (set self.description)") if @description.nil?
    fail("#{custom_service_name} '#{name}' in '#{@environment.name}' requires application") if application.nil?
    fail("#{custom_service_name} '#{name}' in '#{@environment.name} to_k8s doesn\'t know how to deal with multiple groups yet") if @groups.size > 1
    fail("#{custom_service_name} '#{name}' in '#{@environment.name} to_k8s doesn\'t know how to deal with @enable_secondary_site yet") \
      if @enable_secondary_site
    fail "#{custom_service_name} '#{name}' in '#{@environment.name}', you must specify a cpu_request if specifying a cpu_limit" \
      if @cpu_limit && !@cpu_request
  end

  def k8s_app_resources_name
    group = @groups.first
    "#{name}-#{group}-app"
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

  def generate_app_config(_erb_vars, _hiera_provider)
    nil
  end
end
