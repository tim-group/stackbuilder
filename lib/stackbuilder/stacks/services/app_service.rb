require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/kubernetes_resource_bundle'
require 'stackbuilder/support/digest_generator'
require 'json'

module Stacks::Services::AppService
  include Stacks::Services::RabbitMqDependent

  attr_accessor :ajp_port
  attr_accessor :ehcache
  attr_accessor :idea_positions_exports
  attr_accessor :jvm_args
  attr_accessor :sso_port
  attr_accessor :tomcat_session_replication
  attr_accessor :use_ha_mysql_ordering
  attr_accessor :ha_mysql_ordering_exclude
  attr_accessor :scrape_metrics

  # Kubernetes specific attributes
  attr_accessor :jvm_heap
  attr_accessor :headspace

  attr_accessor :application
  alias_method :database_application_name, :application

  def self.extended(object)
    object.configure
  end

  def configure
    @ajp_port = nil
    @disable_http_lb_hack = false
    @ehcache = false
    @idea_positions_exports = false
    @jvm_args = nil
    @ports = { 'app' => { 'port' => 8000, 'service_port' => 80 } }
    @one_instance_in_lb = false
    @sso_port = nil
    @tomcat_session_replication = false
    @use_ha_mysql_ordering = false
    @ha_mysql_ordering_exclude = []
    @jvm_heap = '64M'
    @headspace = 0.1
    @artifact_from_nexus = true
    @monitor_tucker = true
    @security_context = {
      'runAsUser' => 2055,
      'runAsGroup' => 3017,
      'fsGroup' => 3017
    }
    @command = ["/bin/sh"]
    @args = [
      '-c',
      'exec /usr/bin/java $(cat /config/jvm_args) -jar /app/app.jar /config/config.properties'
    ]
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
    @pre_appconfig_template = <<'EOC'
port=8000

log.directory=/var/log/app
log.tags=["env:<%= @logicalenv %>", "app:<%= @application %>", "instance:<%= @group %>"]
<%- if @dependencies.size > 0 -%>
<%- @dependencies.map do |k, v| -%>
<%- if k.start_with?('db.') && k.end_with?('.username') -%>
<%= k %>=<%= v[0,15] + @credentials_selector.to_s %>
<%- elsif k.start_with?('db.') && k.end_with?('password_hiera_key') -%>
<%= k.gsub(/_hiera_key$/, '') %>=<%= secret("#{v}s", @credentials_selector) %>
<%- elsif k.end_with?('_hiera_key') -%>
<%= k.gsub(/_hiera_key$/, '') -%>=<%= secret("#{v}") %>
<%- else -%>
<%= k %>=<%= v %>
<%- end -%>
<%- end -%>
<%- end -%>
EOC
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

  def database_username
    if @kubernetes
      @environment.short_name + @short_name
    else
      @application
    end
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
    deployment['spec']['template']['spec']['initContainers'] = create_init_containers_snippet(secrets, app_name, app_version)
    deployment['spec']['template']['spec']['containers'].first['ports'] << { "containerPort" => 5000, "name" => "jmx" }
    deployment
  end

  def create_app_container_resources_snippet
    ephemeral_storage_limit = @ephemeral_storage_size ? { 'ephemeral-storage' => @ephemeral_storage_size } : {}

    cpu_request = @cpu_request ? { 'cpu' => @cpu_request } : {}
    cpu_limit = @cpu_limit ? { 'cpu' => @cpu_limit } : {}

    {
      'limits' => {
        'memory' => scale_memory(@jvm_heap, @headspace)
      }.merge(ephemeral_storage_limit).merge(cpu_limit),
      'requests' => {
        'memory' => scale_memory(@jvm_heap, @headspace)
      }.merge(ephemeral_storage_limit).merge(cpu_request)
    }
  end

  def create_init_containers_snippet(secrets, app_name, app_version)
    [{
      'image' => 'repo.net.local:8080/timgroup/config-generator:1.0.5',
      'name' => 'config-generator',
      'env' => secrets.map do |_hiera_key, secret_name|
        {
          'name' => "SECRET_#{secret_name}",
          'valueFrom' => {
            'secretKeyRef' => {
              'name' => k8s_app_resources_name,
              'key' => secret_name
            }
          }
        }
      end.push(
        {
          'name' => 'CONTAINER_IMAGE',
          'value' => container_image(app_name, app_version)
        },
        {
          'name' => 'APP_JVM_ARGS',
          'value' => "#{@jvm_args} -Xms#{@jvm_heap} -Xmx#{@jvm_heap}"
        },
        {
          'name' => 'BASE_JVM_ARGS',
          'value' => "-Djava.awt.headless=true -Dfile.encoding=UTF-8 -XX:ErrorFile=/var/log/app/error.log " \
                     "-XX:HeapDumpPath=/var/log/app -XX:+HeapDumpOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom " \
                     "-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=5000 -Dcom.sun.management.jmxremote.authenticate=false " \
                     "-Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote.local.only=false " \
                     "-Dcom.sun.management.jmxremote.rmi.port=5000 -Djava.rmi.server.hostname=127.0.0.1 " \
                     "-Dcom.timgroup.infra.platform=k8s"
        },
        {
          'name' => 'GC_JVM_ARGS_JAVA_8',
          'value' => "-XX:+PrintGC -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -XX:+PrintGCDetails \
-Xloggc:/var/log/app/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=25M \
-XX:+PrintGCApplicationStoppedTime"
        },
        'name' => 'GC_JVM_ARGS_JAVA_11',
        'value' => '-Xlog:gc*,safepoint:/var/log/app/gc.log:time,uptime,level,tags:filecount=10,filesize=26214400'
      ),
      'volumeMounts' => [
        {
          'name' => 'config-volume',
          'mountPath' => '/config'
        },
        {
          'name' => 'config-template',
          'mountPath' => '/input/config.properties',
          'subPath' => 'config.properties'
        }]
    }]
  end
end
