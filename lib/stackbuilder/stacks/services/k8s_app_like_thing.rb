require 'stackbuilder/stacks/kubernetes/namespace'
require 'stackbuilder/stacks/maintainers'
require 'erb'

module Stacks::Services::K8sAppLikeThing
  # Kubernetes specific attributes
  attr_accessor :application
  attr_accessor :headspace
  alias_method :database_application_name, :application

  def self.extended(object)
    object.configure
  end
  def configure
    @headspace = 0.1
    @command = ["/bin/sh"]
    @args = [
      '-c',
      'exec /usr/bin/java $(cat /config/jvm_args) -jar /app/app.jar /config/config.properties'
    ]
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
  end

  # Todo  - waz - do not pass resource into this pat
  def generate_init_container_resource(_resource_name, _app_service_labels, app_name, app_version, _replicas, secrets, _config)
    create_init_containers_snippet(secrets, app_name, app_version)
  end

  private

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
        },
        {
          'name' => 'log-volume',
          'mountPath' => '/var/log/app'
        }
      ]

    }]
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
end
