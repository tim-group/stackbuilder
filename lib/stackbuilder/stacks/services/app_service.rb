require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/kubernetes_resource_bundle'
require 'stackbuilder/stacks/maintainers'
require 'stackbuilder/support/digest_generator'
require 'erb'
require 'json'

module Stacks::Services::AppService
  include Stacks::Services::RabbitMqDependent
  include Stacks::Maintainers

  attr_accessor :ajp_port
  attr_accessor :application
  attr_accessor :ehcache
  attr_accessor :idea_positions_exports
  attr_accessor :jvm_args
  attr_accessor :sso_port
  attr_accessor :tomcat_session_replication
  attr_accessor :use_ha_mysql_ordering
  attr_accessor :ha_mysql_ordering_exclude

  # Kubernetes specific attributes
  attr_accessor :appconfig
  attr_accessor :jvm_heap
  attr_accessor :headspace
  attr_accessor :ephemeral_storage_size
  attr_accessor :enable_service_account
  attr_accessor :cpu_request
  attr_accessor :cpu_limit

  attr_accessor :maintainers
  attr_accessor :description
  attr_accessor :alerts_channel
  attr_accessor :startup_alert_threshold
  attr_accessor :monitor_readiness_probe

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
    @ports = [8000]
    @one_instance_in_lb = false
    @sso_port = nil
    @tomcat_session_replication = false
    @use_ha_mysql_ordering = false
    @ha_mysql_ordering_exclude = []
    @jvm_heap = '64M'
    @headspace = 0.1
    @ephemeral_storage_size = nil
    @maintainers = []
    @enable_service_account = false
    @cpu_request = false
    @cpu_limit = false
    @monitor_readiness_probe = true
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

  def use_service_account
    self.enable_service_account = true
  end

  def rabbitmq_config
    create_rabbitmq_config(@application)
  end

  def k8s_app_resources_name
    group = @groups.first
    "#{name}-#{group}-app"
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

  class ConfigERB < ERB
    attr_reader :used_secrets

    def initialize(template, vars, hiera_provider)
      super(template, nil, '-')
      vars.each { |k, v| instance_variable_set("@#{k}", v) }
      @vars = vars
      @hiera_provider = hiera_provider
      @used_secrets = {}
    end

    def hiera(key, default = nil)
      value = @hiera_provider.lookup(@vars, key, default)
      fail "The hiera value for #{key} is encrypted. \
Use secret(#{key}) instead of hiera(#{key}) in appconfig" if value.is_a?(String) && value.match(/^ENC\[GPG/)
      value
    end

    def secret(key, index = nil)
      secret_name = key.gsub(/[^a-zA-Z0-9]/, '_')
      secret_name += "_#{index}" unless index.nil?
      @used_secrets[key] = secret_name
      "{SECRET:#{secret_name}}"
    end

    def render
      result(binding)
    end
  end

  def to_k8s(app_deployer, dns_resolver, hiera_provider)
    fail("app_service '#{name}' in '#{@environment.name}' requires maintainers (set self.maintainers)") if @maintainers.empty?
    fail("app_service '#{name}' in '#{@environment.name}' requires description (set self.description)") if @description.nil?
    fail("app_service '#{name}' in '#{@environment.name}' requires application") if application.nil?
    fail('app_service to_k8s doesn\'t know how to deal with multiple groups yet') if @groups.size > 1
    fail('app_service to_k8s doesn\'t know how to deal with @enable_secondary_site yet') if @enable_secondary_site

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
      erb_vars = {
        'dependencies' => dependency_config(site, nil),
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
      output << generate_k8s_config_map(app_service_labels, config)
      output << generate_k8s_service(app_service_labels)
      output << generate_k8s_deployment(app_service_labels, app_name, app_version, replicas, used_secrets)
      output << generate_k8s_alerting(site, app_service_labels)
      output += generate_k8s_network_policies(dns_resolver, site, app_service_labels)
      output += generate_k8s_service_account(dns_resolver, site, app_service_labels)

      output += generate_k8s_ingress_resources(dns_resolver, site, standard_labels, app_service_labels)

      Stacks::KubernetesResourceBundle.new(site, @environment.name, app_service_labels, output, used_secrets, hiera_scope, k8s_app_resources_name)
    end
  end

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

  def generate_app_config(erb_vars, hiera_provider)
    template = <<'EOC'
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
    template += appconfig if appconfig

    erb = ConfigERB.new(template, erb_vars, hiera_provider)
    contents = erb.render

    [contents, erb.used_secrets]
  end

  def generate_k8s_config_map(labels, config)
    {
      'apiVersion' => 'v1',
      'kind' => 'ConfigMap',
      'metadata' => {
        'name' => k8s_app_resources_name,
        'namespace' => @environment.name,
        'labels' => labels
      },
      'data' => {
        'config.properties' => config
      }
    }
  end

  def generate_k8s_service(labels)
    {
      'apiVersion' => 'v1',
      'kind' => 'Service',
      'metadata' => {
        'name' => k8s_app_resources_name,
        'namespace' => @environment.name,
        'labels' => labels
      },
      'spec' => {
        'type' => 'ClusterIP',
        'selector' => {
          'machineset' => labels['machineset'],
          'group' => labels['group'],
          'app.kubernetes.io/component' => labels['app.kubernetes.io/component'],
          'participation' => 'enabled'
        },
        'ports' => [{
          'name' => 'app',
          'protocol' => 'TCP',
          'port' => 8000,
          'targetPort' => 8000
        }]
      }
    }
  end

  def generate_k8s_deployment(app_service_labels, app_name, app_version, replicas, secrets)
    labels = app_service_labels.merge('application' => app_name,
                                      'app.kubernetes.io/name' => app_name,
                                      'app.kubernetes.io/version' => app_version)

    container_image = "repo.net.local:8080/timgroup/#{app_name}:#{app_version}"

    annotations = {}
    annotations['maintainers'] = JSON.dump(@maintainers) unless @maintainers.empty?
    annotations['description'] = description unless @description.nil?

    deployment_annotations = {}
    deployment_annotations['configmap.reloader.stakater.com/reload'] = k8s_app_resources_name
    deployment_annotations['secret.reloader.stakater.com/reload'] = k8s_app_resources_name
    deployment_annotations.merge!(annotations)

    pod_annotations = {}
    pod_annotations['seccomp.security.alpha.kubernetes.io/pod'] = 'runtime/default'
    pod_annotations.merge!(annotations)

    ephemeral_storage_limit = @ephemeral_storage_size ? { 'ephemeral-storage' => @ephemeral_storage_size } : {}

    if cpu_limit && !cpu_request
      fail "You must specify a cpu_request if specifying a cpu_limit"
    end

    cpu_request = @cpu_request ? { 'cpu' => @cpu_request } : {}
    cpu_limit = @cpu_limit ? { 'cpu' => @cpu_limit } : {}

    deployment = {
      'apiVersion' => 'apps/v1',
      'kind' => 'Deployment',
      'metadata' => {
        'name' => k8s_app_resources_name,
        'namespace' => @environment.name,
        'labels' => labels,
        'annotations' => deployment_annotations
      },
      'spec' => {
        'selector' => {
          'matchLabels' => {
            'machineset' => labels['machineset'],
            'group' => labels['group'],
            'app.kubernetes.io/component' => labels['app.kubernetes.io/component'],
            'participation' => 'enabled'
          }
        },
        'strategy' => {
          'type' => 'RollingUpdate',
          'rollingUpdate' => { # these settings allow one instance to be taken down and no extras to be created, this replicates orc
            'maxUnavailable' => 1,
            'maxSurge' => 0
          }
        },
        'replicas' => replicas,
        'template' => {
          'metadata' => {
            'labels' => {
              'participation' => 'enabled'
            }.merge(labels),
            'annotations' => pod_annotations
          },
          'spec' => {
            'affinity' => {
              'podAntiAffinity' => {
                'preferredDuringSchedulingIgnoredDuringExecution' => [{
                  'podAffinityTerm' => {
                    'labelSelector' => {
                      'matchLabels' => {
                        'machineset' => labels['machineset'],
                        'group' => labels['group'],
                        'app.kubernetes.io/component' => labels['app.kubernetes.io/component']
                      }
                    },
                    'topologyKey' => 'kubernetes.io/hostname'
                  },
                  'weight' => 100
                }]
              }
            },
            'automountServiceAccountToken' => false,
            'securityContext' => {
              'runAsUser' => 2055,
              'runAsGroup' => 3017,
              'fsGroup' => 3017
            },
            'initContainers' => [{
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
                  'value' => container_image
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
                             "-Dcom.sun.management.jmxremote.rmi.port=5000 -Djava.rmi.server.hostname=127.0.0.1"
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
            }],
            'containers' => [{
              'securityContext' => {
                'readOnlyRootFilesystem' => true,
                'allowPrivilegeEscalation' => false,
                'capabilities' => {
                  'drop' => ['ALL']
                }
              },
              'image' => container_image,
              'name' => app_name,
              'command' => ["/bin/sh"],
              'args' => [
                '-c',
                'exec /usr/bin/java $(cat /config/jvm_args) -jar /app/app.jar /config/config.properties'
              ],
              'resources' => {
                'limits' => {
                  'memory' => scale_memory(@jvm_heap, @headspace) + 'i'
                }.merge(ephemeral_storage_limit).merge(cpu_limit),
                'requests' => {
                  'memory' => scale_memory(@jvm_heap, @headspace) + 'i'
                }.merge(ephemeral_storage_limit).merge(cpu_request)
              },
              'ports' => [
                {
                  'containerPort' => 8000,
                  'name' => 'app'
                },
                {
                  'containerPort' => 5000,
                  'name' => 'jmx'
                }
              ],
              'volumeMounts' => [
                {
                  'name' => 'config-volume',
                  'mountPath' => '/config',
                  'readOnly' => true
                },
                {
                  'name' => 'log-volume',
                  'mountPath' => '/var/log/app'
                },
                {
                  'name' => 'tmp-volume',
                  'mountPath' => '/tmp'
                }
              ],
              'readinessProbe' => {
                'periodSeconds' => 2,
                'timeoutSeconds' => 1,
                'failureThreshold' => 6,
                'httpGet' => {
                  'path' => '/info/ready',
                  'port' => 8000
                }
              },
              'lifecycle' => {
                'preStop' => {
                  'exec' => {
                    'command' => [
                      '/bin/sh',
                      '-c',
                      'sleep 10; while [ "$(curl -s localhost:8000/info/stoppable)" != "safe" ]; do sleep 1; done'
                    ]
                  }
                }
              }
            }],
            'volumes' => [
              {
                'name' => 'config-volume',
                'emptyDir' => {}
              },
              {
                'name' => 'config-template',
                'configMap' => { 'name' => k8s_app_resources_name }
              },
              {
                'name' => 'log-volume',
                'emptyDir' => {}
              },
              {
                'name' => 'tmp-volume',
                'emptyDir' => {}
              }
            ]
          }
        }
      }
    }

    if enable_service_account
      deployment['spec']['template']['spec']['automountServiceAccountToken'] = true
      deployment['spec']['template']['spec']['serviceAccountName'] = k8s_app_resources_name
    end

    deployment
  end

  def generate_k8s_alerting(site, app_service_labels)
    status_critical_alert_labels = { 'severity' => 'critical', 'alertname' => "#{k8s_app_resources_name} CRITICAL" }
    status_critical_alert_labels['alert_owner_channel'] = alerts_channel if alerts_channel

    failed_readiness_alert_labels = {
      'severity' => 'warning',
      'alertname' => "#{k8s_app_resources_name} failed readiness probe when deployment not in progress"
    }
    failed_readiness_alert_labels['alert_owner_channel'] = alerts_channel ? alerts_channel : 'kubernetes-alerts-nonprod'

    rules = []

    rules << {
      'alert' => 'StatusCritical',
      'expr' => "sum(tucker_component_status{job=\"#{k8s_app_resources_name}\",status=\"critical\"}) by (pod, namespace) > 0",
      'labels' => status_critical_alert_labels,
      'annotations' => {
        'message' => '{{ $value }} components are critical on {{ $labels.namespace }}/{{ $labels.pod }}',
        'status_page_url' => "https://go.timgroup.com/insight/#{site}/proxy/{{ $labels.namespace }}/{{ $labels.pod }}/info/status"
      }
    }

    if @monitor_readiness_probe
      rules << {
        'alert' => 'FailedReadinessProbe',
        'expr' => "(((time() - kube_pod_start_time{pod=~\".*#{k8s_app_resources_name}.*\"}) > #{startup_alert_threshold_seconds}) "\
            "and on(pod) (rate(prober_probe_total{probe_type=\"Readiness\",result=\"failed\",pod=~\"^#{k8s_app_resources_name}.*\"}[1m]) > 0))",
        'labels' => failed_readiness_alert_labels,
        'annotations' => {
          'message' => '{{ $labels.namespace }}/{{ $labels.pod }} has failed readiness probe when deployment not in progress',
          'status_page_url' => "https://go.timgroup.com/insight/#{site}/proxy/#{@environment.name}/{{ $labels.pod }}/info/status"
        }
      }
    end

    {
      'apiVersion' => 'monitoring.coreos.com/v1',
      'kind' => 'PrometheusRule',
      'metadata' => {
        'labels' => {
          'prometheus' => 'main',
          'role' => 'alert-rules'
        }.merge(app_service_labels),
        'name' => k8s_app_resources_name,
        'namespace' => @environment.name
      },
      'spec' => {
        'groups' => [
          {
            'name' => 'stacks-alerts',
            'rules' => rules
          }
        ]
      }
    }
  end

  def scale_memory(memory, coeff)
    m = memory.match(/^(\d+)(G|M|K)i?$/)
    byte_conversion_factor = case m.captures[1].upcase
                             when 'G'
                               1024**3
                             when 'M'
                               1024**2
                             when 'K'
                               1024
                             end
    bytes = (1 + coeff) * m.captures[0].to_i * byte_conversion_factor
    "#{(bytes / 1024).floor}K"
  end

  def generate_k8s_network_policies(dns_resolver, site, standard_labels)
    # this method only does the network policies for the app pods
    network_policies = []

    network_policies += generate_k8s_network_policies_for_dependents(dns_resolver, site, standard_labels)
    network_policies += generate_k8s_network_policies_for_dependencies(dns_resolver, site, standard_labels)

    nexus_filters = [{
      'to' => [{ 'ipBlock' => { 'cidr' => "#{dns_resolver.lookup('office-nexus-001.mgmt.lon.net.local')}/32" } }],
      'ports' => [{
        'protocol' => 'TCP',
        'port' => 8080
      }]
    }]
    ingress_match_labels = {
      'machineset' => standard_labels['machineset'],
      'group' => standard_labels['group'],
      'app.kubernetes.io/component' => 'app_service'
    }
    network_policies << create_egress_network_policy('off', 'nexus', @environment.name, standard_labels,
                                                     nexus_filters, ingress_match_labels)

    prom_filters = [generate_pod_and_namespace_selector_filter('monitoring', 'prometheus' => 'main')]
    network_policies << create_ingress_network_policy_for_internal_service('mon', 'prom-main',
                                                                           @environment.name, standard_labels,
                                                                           prom_filters)

    network_policies
  end

  def generate_k8s_service_account(dns_resolver, site, standard_labels)
    if enable_service_account

      network_policy_spec = {
        'podSelector' => {
          'matchLabels' => {
            'machineset' => standard_labels['machineset'],
            'group' => standard_labels['group'],
            'app.kubernetes.io/component' => 'app_service'
          }
        },
        'policyTypes' => [
          'Egress'
        ],

        'egress' => [{
          'to' => [{
            'ipBlock' => {
              'cidr' => "#{dns_resolver.lookup("#{site}-kube-apiserver-vip.mgmt.#{site}.net.local")}/32"
            }
          }],
          'ports' => [{
            'protocol' => 'TCP',
            'port' => 6443
          }]
        }]
      }

      hash = Support::DigestGenerator.from_hash(network_policy_spec)

      [{
        'apiVersion' => 'v1',
        'kind' => 'ServiceAccount',
        'metadata' => {
          'namespace' => @environment.name,
          'name' => k8s_app_resources_name,
          'labels' => standard_labels
        }
      }, {
        'apiVersion' => 'networking.k8s.io/v1',
        'kind' => 'NetworkPolicy',
        'metadata' => {
          'name' => "allow-out-to-#{site}-kubernetes-api-#{hash}",
          'namespace' => @environment.name,
          'labels' => standard_labels
        },
        'spec' => network_policy_spec
      }]
    else
      []
    end
  end

  def create_ingress_network_policy_for_external_service(virtual_service_env, virtual_service_name, env_name, labels, filters)
    spec = {
      'podSelector' => {
        'matchLabels' => {
          'machineset' => labels['machineset'],
          'group' => labels['group'],
          'app.kubernetes.io/component' => 'ingress'
        }
      },
      'policyTypes' => [
        'Ingress'
      ],
      'ingress' => [{
        'from' => filters,
        'ports' => [{
          'protocol' => 'TCP',
          'port' => 'http'
        }]
      }]
    }

    hash = Support::DigestGenerator.from_hash(spec)

    {
      'apiVersion' => 'networking.k8s.io/v1',
      'kind' => 'NetworkPolicy',
      'metadata' => {
        'name' => "allow-in-from-#{virtual_service_env}-#{virtual_service_name}-#{hash}",
        'namespace' => env_name,
        'labels' => labels
      },
      'spec' => spec
    }
  end

  def create_ingress_network_policy_for_internal_service(virtual_service_env, virtual_service_name, env_name, labels, filters)
    spec = {
      'podSelector' => {
        'matchLabels' => {
          'machineset' => labels['machineset'],
          'group' => labels['group'],
          'app.kubernetes.io/component' => 'app_service'
        }
      },
      'policyTypes' => [
        'Ingress'
      ],
      'ingress' => [{
        'from' => filters,
        'ports' => [{
          'protocol' => 'TCP',
          'port' => 'app'
        }]
      }]
    }

    hash = Support::DigestGenerator.from_hash(spec)

    {
      'apiVersion' => 'networking.k8s.io/v1',
      'kind' => 'NetworkPolicy',
      'metadata' => {
        'name' => "allow-in-from-#{virtual_service_env}-#{virtual_service_name}-#{hash}",
        'namespace' => env_name,
        'labels' => labels
      },
      'spec' => spec
    }
  end

  def create_ingress_network_policy_to_ingress_for_internal_service(virtual_service_env, virtual_service_name,
                                                                    env_name, labels, port, filters)
    spec = {
      'podSelector' => {
        'matchLabels' => {
          'machineset' => labels['machineset'],
          'group' => labels['group'],
          'app.kubernetes.io/component' => 'ingress'
        }
      },
      'policyTypes' => [
        'Ingress'
      ],
      'ingress' => [{
        'from' => filters,
        'ports' => [{
          'protocol' => 'TCP',
          'port' => port
        }]
      }]
    }

    hash = Support::DigestGenerator.from_hash(spec)

    {
      'apiVersion' => 'networking.k8s.io/v1',
      'kind' => 'NetworkPolicy',
      'metadata' => {
        'name' => "allow-in-from-#{virtual_service_env}-#{virtual_service_name}-#{hash}",
        'namespace' => env_name,
        'labels' => labels
      },
      'spec' => spec
    }
  end

  def create_egress_network_policy(virtual_service_env, virtual_service_name, env_name,
                                   labels, egresses, pod_selector_match_labels)
    spec = {
      'podSelector' => {
        'matchLabels' => pod_selector_match_labels
      },
      'policyTypes' => [
        'Egress'
      ],
      'egress' => egresses
    }

    hash = Support::DigestGenerator.from_hash(spec)

    {
      'apiVersion' => 'networking.k8s.io/v1',
      'kind' => 'NetworkPolicy',
      'metadata' => {
        'name' => "allow-out-to-#{virtual_service_env}-#{virtual_service_name}-#{hash}",
        'namespace' => env_name,
        'labels' => labels
      },
      'spec' => spec
    }
  end

  def create_egress_network_policy_for_external_service(service_name, env_name, labels, egresses, pod_selector_match_labels)
    spec = {
      'podSelector' => {
        'matchLabels' => pod_selector_match_labels
      },
      'policyTypes' => [
        'Egress'
      ],
      'egress' => egresses
    }

    hash = Support::DigestGenerator.from_hash(spec)

    {
      'apiVersion' => 'networking.k8s.io/v1',
      'kind' => 'NetworkPolicy',
      'metadata' => {
        'name' => "allow-out-to-#{service_name}-#{hash}",
        'namespace' => env_name,
        'labels' => labels
      },
      'spec' => spec
    }
  end

  def generate_k8s_ingress(name, labels)
    {
      'apiVersion' => 'networking.k8s.io/v1beta1',
      'kind' => 'Ingress',
      'metadata' => {
        'name' => name,
        'namespace' => @environment.name,
        'labels' => labels,
        'annotations' => {
          'kubernetes.io/ingress.class' => "traefik-#{labels['machineset']}-#{labels['group']}"
        }
      },
      'spec' => {
        'rules' => [{
          'http' => {
            'paths' => [{
              'path' => '/',
              'backend' => {
                'serviceName' => name,
                'servicePort' => 8000
              }
            }]
          }
        }]
      }
    }
  end

  def generate_k8s_ingress_controller_role(name, ingress_labels)
    {
      'kind' => 'Role',
      'apiVersion' => 'rbac.authorization.k8s.io/v1',
      'metadata' => {
        'name' => name,
        'namespace' => @environment.name,
        'labels' => ingress_labels
      },
      'rules' => [
        {
          'apiGroups' => [
            ""
          ],
          'resources' => %w(services endpoints),
          'verbs' => %w(get list watch)
        },
        {
          "apiGroups" => [
            "extensions",
            "networking.k8s.io"
          ],
          "resources" => [
            "ingresses"
          ],
          "verbs" => %w(get list watch)
        },
        {
          "apiGroups" => [
            "extensions",
            "networking.k8s.io"
          ],
          "resources" => [
            "ingresses/status"
          ],
          "verbs" => [
            "update"
          ]
        }
      ]
    }
  end

  def generate_k8s_ingress_controller_network_policies(_name, ingress_labels, dns_resolver, site)
    network_policies = []

    app_service_match_labels = {
      'machineset' => ingress_labels['machineset'],
      'group' => 'blue',
      'app.kubernetes.io/component' => 'app_service'
    }
    egresses = [{
      'to' => [
        generate_pod_and_namespace_selector_filter(@environment.name, app_service_match_labels)
      ],
      'ports' => [{
        'protocol' => 'TCP',
        'port' => 'app'
      }]
    }]
    ingress_match_labels = {
      'machineset' => ingress_labels['machineset'],
      'group' => 'blue',
      'app.kubernetes.io/component' => 'ingress'
    }
    network_policies << create_egress_network_policy(@environment.short_name, short_name, @environment.name, ingress_labels, egresses, ingress_match_labels)

    api_server_egresses = [{
      'to' => [{
        'ipBlock' => {
          'cidr' => '10.50.0.1/32'
        }
      }],
      'ports' => [{
        'port' => 443,
        'protocol' => 'TCP'
      }]
    }]

    network_policies << create_egress_network_policy_for_external_service('api-server', @environment.name, ingress_labels,
                                                                          api_server_egresses, ingress_match_labels)

    virtual_services_that_depend_on_me.each do |vs|
      is_same_site = requirements_of(vs).include?(:same_site)
      next if is_same_site && !vs.exists_in_site?(vs.environment, site)

      next if vs.kubernetes

      filters = []
      dependant_vms = vs.children.select { |vm| vm.site == (is_same_site ? site : @environment.primary_site) }.sort_by(&:prod_fqdn)

      dependant_vms.each do |vm|
        filters << {
          'ipBlock' => {
            'cidr' => "#{dns_resolver.lookup(vm.qualified_hostname(@environment.primary_network))}/32"
          }
        }
      end
      network_policies << create_ingress_network_policy_for_external_service(vs.environment.short_name, vs.short_name,
                                                                             @environment.name, ingress_labels, filters)
    end

    prom_filters = [generate_pod_and_namespace_selector_filter('monitoring', 'prometheus' => 'main')]
    network_policies << create_ingress_network_policy_to_ingress_for_internal_service('mon', 'prom-main',
                                                                                      @environment.name, ingress_labels,
                                                                                      'traefik', prom_filters)

    network_policies
  end

  def generate_k8s_ingress_controller_service(name, ingress_labels, dns_resolver, site)
    {
      'apiVersion' => 'v1',
      'kind' => 'Service',
      'metadata' => {
        'labels' => ingress_labels,
        'name' => name,
        'namespace' => @environment.name,
        'annotations' => {
          'metallb.universe.tf/address-pool' => 'prod-static'
        }
      },
      'spec' => {
        'type' => 'LoadBalancer',
        'loadBalancerIP' => dns_resolver.lookup(prod_fqdn(site)).to_s,
        'externalTrafficPolicy' => 'Local',
        'selector' => {
          'machineset' => ingress_labels['machineset'],
          'group' => ingress_labels['group'],
          'app.kubernetes.io/component' => 'ingress'
        },
        'ports' => [
          {
            'name' => 'http',
            'port' => 80,
            'protocol' => 'TCP',
            'targetPort' => 'http'
          }
        ]
      }
    }
  end

  def generate_k8s_ingress_controller_monitoring_service(name, ingress_labels)
    {
      'apiVersion' => 'v1',
      'kind' => 'Service',
      'metadata' => {
        'labels' => ingress_labels.merge('app.kubernetes.io/component' => 'ingress-monitoring'),
        'name' => "#{name}-mon",
        'namespace' => @environment.name
      },
      'spec' => {
        'clusterIP' => 'None',
        'selector' => {
          'machineset' => ingress_labels['machineset'],
          'group' => ingress_labels['group'],
          'app.kubernetes.io/component' => 'ingress'
        },
        'ports' => [
          {
            'name' => 'traefik',
            'port' => 10254,
            'protocol' => 'TCP',
            'targetPort' => 'traefik'
          }
        ]
      }
    }
  end

  def generate_k8s_ingress_controller_deployment(name, ingress_labels)
    ingress_controller_labels = ingress_labels.merge('app.kubernetes.io/name' => 'traefik',
                                                     'application' => 'traefik',
                                                     'app.kubernetes.io/version' => '2.0')

    {
      'apiVersion' => 'apps/v1',
      'kind' => 'Deployment',
      'metadata' => {
        'name' => name,
        'namespace' => @environment.name,
        'labels' => ingress_controller_labels
      },
      'spec' => {
        'replicas' => 2,
        'selector' => {
          'matchLabels' => {
            'machineset' => ingress_labels['machineset'],
            'group' => ingress_labels['group'],
            'app.kubernetes.io/component' => ingress_labels['app.kubernetes.io/component']
          }
        },
        'template' => {
          'metadata' => {
            'labels' => ingress_controller_labels
          },
          'spec' => {
            'containers' => [
              {
                'args' => [
                  "--accesslog",
                  "--ping",
                  "--api.insecure",
                  "--api.dashboard",
                  "--entrypoints.http.Address=:8000",
                  "--entrypoints.traefik.Address=:10254",
                  "--providers.kubernetesingress",
                  "--providers.kubernetesingress.ingressclass=traefik-#{ingress_labels['machineset']}-#{ingress_labels['group']}",
                  "--providers.kubernetesingress.ingressendpoint.publishedservice=#{@environment.name}/#{name}",
                  "--providers.kubernetesingress.namespaces=#{@environment.name}",
                  "--metrics.prometheus",
                  "--log.level=DEBUG"
                ],
                'image' => 'repo.net.local:8080/timgroup/traefik:tim1',
                'imagePullPolicy' => 'IfNotPresent',
                'livenessProbe' => {
                  'failureThreshold' => 3,
                  'httpGet' => {
                    'path' => '/ping',
                    'port' => 'traefik',
                    'scheme' => 'HTTP'
                  },
                  'initialDelaySeconds' => 10,
                  'periodSeconds' => 10,
                  'successThreshold' => 1,
                  'timeoutSeconds' => 10
                },
                'name' => 'traefik-ingress-controller',
                'ports' => [
                  {
                    'containerPort' => 8000,
                    'name' => 'http',
                    'protocol' => 'TCP'
                  },
                  {
                    'containerPort' => 10254,
                    'name' => 'traefik',
                    'protocol' => 'TCP'
                  }
                ],
                'readinessProbe' => {
                  'failureThreshold' => 3,
                  'httpGet' => {
                    'path' => '/ping',
                    'port' => 'traefik',
                    'scheme' => 'HTTP'
                  },
                  'periodSeconds' => 10,
                  'successThreshold' => 1,
                  'timeoutSeconds' => 10
                },
                'resources' => {
                  'limits' => {
                    'cpu' => '300m',
                    'memory' => '64Mi'
                  },
                  'requests' => {
                    'cpu' => '200m',
                    'memory' => '48Mi'
                  }
                },
                'terminationMessagePath' => '/dev/termination-log',
                'terminationMessagePolicy' => 'File'
              }
            ],
            'serviceAccountName' => name,
            'terminationGracePeriodSeconds' => 60
          }
        }
      }
    }
  end

  def generate_k8s_ingress_controller_service_account(name, ingress_labels)
    {
      'kind' => 'ServiceAccount',
      'apiVersion' => 'v1',
      'metadata' => {
        'name' => name,
        'namespace' => @environment.name,
        'labels' => ingress_labels
      }
    }
  end

  def generate_k8s_ingress_controller_role_binding(name, ingress_labels)
    {
      'kind' => 'RoleBinding',
      'apiVersion' => 'rbac.authorization.k8s.io/v1',
      'metadata' => {
        'name' => name,
        'namespace' => @environment.name,
        'labels' => ingress_labels
      },
      'roleRef' => {
        'apiGroup' => 'rbac.authorization.k8s.io',
        'kind' => 'Role',
        'name' => name
      },
      'subjects' => [{
        'kind' => 'ServiceAccount',
        'name' => name
      }]
    }
  end

  def generate_k8s_ingress_resources(dns_resolver, site, standard_labels, app_service_labels)
    output = []
    non_k8s_deps = virtual_services_that_depend_on_me.select do |vs|
      !vs.kubernetes
    end

    if non_k8s_deps.size > 0
      ingress_labels = standard_labels.merge('app.kubernetes.io/component' => 'ingress')

      k8s_ingress_resources_name = "#{standard_labels['machineset']}-#{standard_labels['group']}-ing"

      output << generate_k8s_ingress(k8s_app_resources_name, app_service_labels)
      output << generate_k8s_ingress_controller_service_account(k8s_ingress_resources_name, ingress_labels)
      output << generate_k8s_ingress_controller_role(k8s_ingress_resources_name, ingress_labels)
      output << generate_k8s_ingress_controller_role_binding(k8s_ingress_resources_name, ingress_labels)
      output += generate_k8s_ingress_controller_network_policies(k8s_ingress_resources_name, ingress_labels, dns_resolver, site)
      output << generate_k8s_ingress_controller_service(k8s_ingress_resources_name, ingress_labels, dns_resolver, site)
      output << generate_k8s_ingress_controller_monitoring_service(k8s_ingress_resources_name, ingress_labels)
      output << generate_k8s_ingress_controller_deployment(k8s_ingress_resources_name, ingress_labels)
    end
    output
  end

  def generate_pod_and_namespace_selector_filter(namespace, match_labels)
    {
      'podSelector' => {
        'matchLabels' => match_labels
      },
      'namespaceSelector' => {
        'matchLabels' => {
          'name' => namespace
        }
      }
    }
  end

  def generate_k8s_network_policies_for_dependents(_dns_resolver, site, standard_labels)
    network_policies = []

    if non_k8s_dependencies_exist?
      ingress_selector = {
        'machineset' => name,
        'group' => @groups.first,
        'app.kubernetes.io/component' => 'ingress'
      }
      ingress_filters = [generate_pod_and_namespace_selector_filter(@environment.name, ingress_selector)]
      network_policies << create_ingress_network_policy_for_internal_service(@environment.short_name, "#{name}-#{@groups.first}-ing",
                                                                             @environment.name, standard_labels,
                                                                             ingress_filters)

      virtual_services_that_depend_on_me.each do |vs|
        is_same_site = requirements_of(vs).include?(:same_site)
        next if is_same_site && !vs.exists_in_site?(vs.environment, site)

        next if !vs.kubernetes

        match_labels = {
          'machineset' => vs.name,
          'group' => vs.groups.first,
          'app.kubernetes.io/component' => 'app_service'
        }
        filters = [generate_pod_and_namespace_selector_filter(vs.environment.name, match_labels)]
        network_policies << create_ingress_network_policy_for_internal_service(vs.environment.short_name, vs.short_name,
                                                                               @environment.name, standard_labels, filters)
      end
    else
      virtual_services_that_depend_on_me.each do |vs|
        is_same_site = requirements_of(vs).include?(:same_site)
        next if is_same_site && !vs.exists_in_site?(vs.environment, site)

        match_labels = {
          'machineset' => vs.name,
          'group' => vs.groups.first,
          'app.kubernetes.io/component' => 'app_service'
        }
        filters = [generate_pod_and_namespace_selector_filter(vs.environment.name, match_labels)]
        network_policies << create_ingress_network_policy_for_internal_service(vs.environment.short_name, vs.short_name,
                                                                               @environment.name, standard_labels, filters)
      end
    end

    network_policies
  end

  def generate_k8s_network_policies_for_dependencies(dns_resolver, site, standard_labels)
    network_policies = []
    virtual_services_that_i_depend_on(false).each do |vs|
      fail "Dependency '#{vs.name}' is not supported for k8s - endpoints method is not implemented" if !vs.respond_to?(:endpoints)

      chosen_site_of_vs = vs.exists_in_site?(vs.environment, site) ? site : vs.environment.primary_site
      endpoints = vs.endpoints(self, chosen_site_of_vs)

      egresses = []
      if vs.kubernetes
        match_labels = {
          'machineset' => vs.name,
          'group' => vs.groups.first,
          'app.kubernetes.io/component' => 'app_service'
        }
        egresses << {
          'to' => [
            generate_pod_and_namespace_selector_filter(vs.environment.name, match_labels)
          ],
          'ports' => [{
            'protocol' => 'TCP',
            'port' => 'app'
          }]
        }
      else
        endpoints.each do |e|
          ip_blocks = []
          e[:fqdns].uniq.each do |fqdn|
            ip_blocks << { 'ipBlock' => { 'cidr' => "#{dns_resolver.lookup(fqdn)}/32" } }
          end
          egresses << {
            'to' => ip_blocks,
            'ports' => [{
              'protocol' => 'TCP',
              'port' => e[:port]
            }]
          }
        end
      end
      app_service_match_labels = {
        'machineset' => standard_labels['machineset'],
        'group' => standard_labels['group'],
        'app.kubernetes.io/component' => 'app_service'
      }
      network_policies << create_egress_network_policy(vs.environment.short_name, vs.short_name, @environment.name,
                                                       standard_labels, egresses, app_service_match_labels)
    end
    network_policies
  end

  def non_k8s_dependencies_exist?
    virtual_services_that_depend_on_me.count { |vs| !vs.kubernetes } > 0
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
end
