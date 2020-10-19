require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/kubernetes_resource_bundle'
require 'stackbuilder/support/digest_generator'
require 'json'

module Stacks::Services::AppService
  include Stacks::Services::RabbitMqDependent
  include Stacks::Services::SharedAppLikeThing

  attr_accessor :ajp_port
  attr_accessor :ehcache
  attr_accessor :idea_positions_exports
  attr_accessor :sso_port
  attr_accessor :tomcat_session_replication
  attr_accessor :scrape_metrics
  attr_accessor :jvm_args
  attr_accessor :jvm_heap

  def self.extended(object)
    object.configure
  end

  def configure
    super
    @ajp_port = nil
    @disable_http_lb_hack = false
    @ehcache = false
    @idea_positions_exports = false
    @ports = {
      # The app port is what the service is actually served on. It gets exposed
      # to all other stacks that depend on it. If any of those are outside the
      # k8s cluster, then an ingress is created to allow that.
      'app' => { 'port' => 8000, 'service_port' => 80, 'protocol' => 'tcp' },

      # The metrics port is only accessed by Prometheus.
      'metrics' => { 'port' => 8001, 'service_port' => 8001, 'protocol' => 'tcp' }
    }
    @one_instance_in_lb = false
    @sso_port = nil
    @tomcat_session_replication = false
    @artifact_from_nexus = true
    @monitor_tucker = true
    @security_context = {
      'runAsUser' => 2055,
      'runAsGroup' => 3017,
      'fsGroup' => 3017
    }
    @jvm_args = nil
    @jvm_heap = '64M'
    @readiness_probe = {
      'periodSeconds' => 2,
      'timeoutSeconds' => 1,
      'failureThreshold' => 6,
      'httpGet' => {
        'path' => '/info/ready',
        'port' => 8000
      }
    }
    @lifecycle_pre_stop = {
      'exec' => {
        'command' => [
          '/bin/sh',
          '-c',
          'sleep 10; while [ "$(curl -s localhost:8000/info/stoppable)" != "safe" ]; do sleep 1; done'
        ]
      }
    }
    @log_volume_mount_path = '/var/log/app'
    @scrape_metrics = true
  end

  def enable_ehcache
    @ehcache = true
  end

  def enable_sso(sso_port = '8443')
    @sso_port = sso_port
  end

  def enable_ajp(ajp_port = '8009')
    @ajp_port = ajp_port
  end

  def enable_tomcat_session_replication
    @tomcat_session_replication = true
  end

  def disable_http_lb_hack
    @disable_http_lb_hack = true
  end

  def rabbitmq_config
    create_rabbitmq_config(@application)
  end

  def endpoints(_dependent_service, fabric)
    [{ :port => 8000, :fqdns => [prod_fqdn(fabric)] }]
  end

  def config_params(dependant, fabric, _dependent_instance)
    if respond_to? :vip_fqdn
      fail("app_service requires application") if application.nil?
      url = if @kubernetes
              if dependant.kubernetes
                "http://#{k8s_app_resources_name}.#{environment.name}.svc"
              else
                "http://#{prod_fqdn(fabric)}"
              end
            else
              "http://#{prod_fqdn(fabric)}:8000"
            end
      { "#{application.downcase}.url" => url }
    else
      {}
    end
  end

  def to_loadbalancer_config(location, fabric)
    if @disable_http_lb_hack && @one_instance_in_lb
      fail('disable_http_lb_hack and one_instance_in_lb cannot be specified at the same time')
    end
    config = {}
    if respond_to?(:load_balanced_service?) && !(respond_to?(:kubernetes) && kubernetes)
      config = loadbalancer_config(location, fabric)
      unless @sso_port.nil? || config.empty?
        if @disable_http_lb_hack
          config[vip_fqdn(:prod, fabric)]['type'] = 'sso_app'
        else
          config[vip_fqdn(:prod, fabric)]['type'] = 'http_and_sso_app'
        end
      end
    end
    if @one_instance_in_lb && !config.empty?
      config[vip_fqdn(:prod, fabric)]['type'] = 'one_instance_in_lb_with_sorry_server'
    end
    config
  end

  # FIXME: For some reason this can't move into base_k8s_app?!
  def prod_fqdn(fabric)
    if respond_to? :vip_fqdn
      vip_fqdn(:prod, fabric)
    else
      children.first.prod_fqdn
    end
  end

  private

  def instance_name_of(service)
    "#{service.environment.short_name}-#{service.short_name}"
  end

  def generate_app_deployment_resource(resource_name, app_service_labels, app_name, app_version, replicas, secrets, config)
    deployment = super
    deployment['spec']['template']['spec']['initContainers'] =
      generate_init_container_resource(resource_name, app_service_labels, app_name, app_version, replicas, secrets, config)
    deployment['spec']['template']['spec']['containers'].first['ports'] << { "containerPort" => 5000, "name" => "jmx" }
    deployment
  end
end
