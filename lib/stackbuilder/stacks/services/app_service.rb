require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/kubernetes_resource_bundle'
require 'stackbuilder/stacks/maintainers'
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

  attr_accessor :maintainers
  attr_accessor :description

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

  def config_params(_dependant, fabric, _dependent_instance)
    if respond_to? :vip_fqdn
      fail("app_service requires application") if application.nil?
      { "#{application.downcase}.url" => "http://#{prod_fqdn(fabric)}:8000" }
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
        'app.kubernetes.io/name' => app_name,
        'app.kubernetes.io/instance' => instance_name_of(self),
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => app_version.to_s,
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => @stack.name,
        'machineset' => name
      }

      config, used_secrets = generate_app_config(erb_vars, hiera_provider)

      output = super app_deployer, dns_resolver, hiera_provider, standard_labels
      output << generate_k8s_config_map(config, standard_labels)
      output << generate_k8s_service(dns_resolver, site, standard_labels)
      output << generate_k8s_deployment(standard_labels, replicas, used_secrets)
      output += generate_k8s_network_policies(dns_resolver, site, standard_labels)
      output += generate_k8s_service_account(dns_resolver, site, standard_labels)
      Stacks::KubernetesResourceBundle.new(site, @environment.name, @stack.name, name, standard_labels, output, used_secrets, hiera_scope)
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
    "#{service.environment.name}-#{service.stack.name}-#{service.short_name}"
  end

  def generate_app_config(erb_vars, hiera_provider)
    template = <<'EOC'
port=8000

log.directory=/var/log/app
log.tags=["env:<%= @logicalenv %>", "app:<%= @application %>", "instance:<%= @group %>"]

graphite.enabled=false
graphite.host=<%= @site %>-mon-001.mgmt.<%= @site %>.net.local
graphite.port=2013
graphite.prefix=<%= @application.downcase %>.k8s_<%= @logicalenv %>_<%= @site %>
graphite.period=10
<%- if @dependencies.size > 0 -%>
<%- @dependencies.map do |k, v| -%>
<%- if k.start_with?('db.') && k.end_with?('.username') -%>
<%= k %>=<%= v[0,15] + @credentials_selector.to_s %>
<%- elsif k.start_with?('db.') && k.end_with?('password_hiera_key') -%>
<%= k.gsub(/_hiera_key$/, '') %>=<%= secret("#{v}s", @credentials_selector) %>
<%# TODO: support non-db _hiera_key. For example for a rabbitmq connection -%>
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

  def generate_k8s_config_map(config, standard_labels)
    app_name = standard_labels['app.kubernetes.io/name']

    {
      'apiVersion' => 'v1',
      'kind' => 'ConfigMap',
      'metadata' => {
        'name' => app_name + '-config',
        'namespace' => @environment.name,
        'labels' => standard_labels
      },
      'data' => {
        'config.properties' => config
      }
    }
  end

  def generate_k8s_service(dns_resolver, site, standard_labels)
    app_name = standard_labels['app.kubernetes.io/name']

    {
      'apiVersion' => 'v1',
      'kind' => 'Service',
      'metadata' => {
        'name' => app_name,
        'namespace' => @environment.name,
        'labels' => standard_labels,
        'annotations' => {
          'metallb.universe.tf/address-pool' => 'prod-static'
        }
      },
      'spec' => {
        'type' => 'LoadBalancer',
        'selector' => {
          'app.kubernetes.io/instance' => standard_labels['app.kubernetes.io/instance'],
          'participation' => 'enabled'
        },
        'ports' => [{
          'name' => 'app',
          'protocol' => 'TCP',
          'port' => 8000,
          'targetPort' => 8000
        }],
        'loadBalancerIP' => dns_resolver.lookup(prod_fqdn(site)).to_s
      }
    }
  end

  def generate_k8s_deployment(standard_labels, replicas, secrets)
    app_name = standard_labels['app.kubernetes.io/name']
    app_version = standard_labels['app.kubernetes.io/version']
    container_image = "repo.net.local:8080/#{app_name}:#{app_version}"

    annotations = {}
    annotations['maintainers'] = JSON.dump(@maintainers) unless @maintainers.empty?
    annotations['description'] = description unless @description.nil?

    deployment_annotations = {}
    deployment_annotations['configmap.reloader.stakater.com/reload'] = app_name + '-config'
    deployment_annotations['secret.reloader.stakater.com/reload'] = app_name + '-secret'
    deployment_annotations.merge!(annotations)

    pod_annotations = {}
    pod_annotations['seccomp.security.alpha.kubernetes.io/pod'] = 'runtime/default'
    pod_annotations.merge!(annotations)

    ephemeral_storage_limit = @ephemeral_storage_size ? { 'ephemeral-storage' => @ephemeral_storage_size } : {}

    deployment = {
      'apiVersion' => 'apps/v1',
      'kind' => 'Deployment',
      'metadata' => {
        'name' => app_name,
        'namespace' => @environment.name,
        'labels' => standard_labels,
        'annotations' => deployment_annotations
      },
      'spec' => {
        'selector' => {
          'matchLabels' => {
            'app.kubernetes.io/instance' => standard_labels['app.kubernetes.io/instance'],
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
            }.merge(standard_labels),
            'annotations' => pod_annotations
          },
          'spec' => {
            'automountServiceAccountToken' => false,
            'securityContext' => {
              'runAsUser' => 2055,
              'runAsGroup' => 3017,
              'fsGroup' => 3017
            },
            'initContainers' => [{
              'image' => 'repo.net.local:8080/config-generator:1.0.5',
              'name' => 'config-generator',
              'env' => secrets.map do |_hiera_key, secret_name|
                {
                  'name' => "SECRET_#{secret_name}",
                  'valueFrom' => {
                    'secretKeyRef' => {
                      'name' => "#{app_name}-secret",
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
                  'value' => "#{@jvm_args} -Xmx#{@jvm_heap}"
                },
                {
                  'name' => 'BASE_JVM_ARGS',
                  'value' => "-Djava.awt.headless=true -Dfile.encoding=UTF-8 -XX:ErrorFile=/var/log/app/error.log \
-XX:HeapDumpPath=/var/log/app -XX:+HeapDumpOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom \
-Dcom.sun.management.jmxremote.port=5000 -Dcom.sun.management.jmxremote.authenticate=false \
-Dcom.sun.management.jmxremote.ssl=false"
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
                }.merge(ephemeral_storage_limit),
                'requests' => {
                  'memory' => scale_memory(@jvm_heap, @headspace) + 'i'
                }.merge(ephemeral_storage_limit)
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
                'configMap' => { 'name' => "#{app_name}-config" }
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
      deployment['spec']['template']['spec']['serviceAccountName'] = name
    end

    deployment
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
    network_policies = []
    virtual_services_that_depend_on_me.each do |vs|
      next if requirements_of(vs).include?(:same_site) && !vs.exists_in_site?(vs.environment, site)

      filters = []
      if vs.kubernetes
        filters << {
          'podSelector' => {
            'matchLabels' => {
              'app.kubernetes.io/instance' => instance_name_of(vs)
            }
          },
          'namespaceSelector' => {
            'matchLabels' => {
              'name' => vs.environment.name
            }
          }
        }
      else
        virtual_service_instance_fqdns = dependant_instance_fqdns(location, [@environment.primary_network])
        virtual_service_instance_fqdns.each do |instance_fqdn|
          filters << {
            'ipBlock' => {
              'cidr' => "#{dns_resolver.lookup(instance_fqdn)}/32"
            }
          }
        end
      end

      network_policies << create_ingress_network_policy(vs.environment.name, vs.short_name, @name, @environment.name, standard_labels, filters)
    end

    virtual_services_that_i_depend_on(false).each do |vs|
      fail "Dependency '#{vs.name}' is not supported for k8s - endpoints method is not implemented" if !vs.respond_to?(:endpoints)

      chosen_site_of_vs = vs.exists_in_site?(vs.environment, site) ? site : vs.environment.primary_site
      endpoints = vs.endpoints(self, chosen_site_of_vs)

      egresses = []
      if vs.kubernetes
        egresses << {
          'to' => [{
            'podSelector' => {
              'matchLabels' => {
                'app.kubernetes.io/instance' => instance_name_of(vs)
              }
            },
            'namespaceSelector' => {
              'matchLabels' => {
                'name' => vs.environment.name
              }
            }
          }],
          'ports' => [{
            'protocol' => 'TCP',
            'port' => 8000
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
      ports = endpoints.map { |e| e[:port] }.join('-')
      network_policies << create_egress_network_policy(vs.environment.name, vs.short_name, @name, @environment.name, standard_labels, ports, egresses)
    end

    nexus_filters = [{
      'to' => [{ 'ipBlock' => { 'cidr' => "#{dns_resolver.lookup('office-nexus-001.mgmt.lon.net.local')}/32" } }],
      'ports' => [{
        'protocol' => 'TCP',
        'port' => 8080
      }]
    }]

    network_policies << create_egress_network_policy('office', 'nexus', @name, @environment.name, standard_labels, '8080', nexus_filters)

    filters = []
    %w(001 002).each do |server_index|
      filters << {
        'ipBlock' => {
          'cidr' => "#{dns_resolver.lookup("production-sharedproxy-#{server_index}.#{site}.net.local")}/32"
        }
      }
    end

    network_policies << create_ingress_network_policy('production', 'sharedproxy', @name, @environment.name, standard_labels, filters)

    network_policies
  end

  def generate_k8s_service_account(dns_resolver, site, standard_labels)
    if enable_service_account
      [{
        'apiVersion' => 'v1',
        'kind' => 'ServiceAccount',
        'metadata' => {
          'namespace' => @environment.name,
          'name' => @name,
          'labels' => standard_labels
        }
      }, {
        'apiVersion' => 'networking.k8s.io/v1',
        'kind' => 'NetworkPolicy',
        'metadata' => {
          'name' => "allow-#{@name}-out-to-#{site}-kubernetes-api-6443",
          'namespace' => @environment.name,
          'labels' => standard_labels
        },
        'spec' => {
          'podSelector' => {
            'matchLabels' => {
              'app.kubernetes.io/instance' => standard_labels['app.kubernetes.io/instance']
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
      }]
    else
      []
    end
  end

  def create_ingress_network_policy(virtual_service_env, virtual_service_name, app_name, env_name, standard_labels, filters)
    {
      'apiVersion' => 'networking.k8s.io/v1',
      'kind' => 'NetworkPolicy',
      'metadata' => {
        'name' => "allow-#{virtual_service_env}-#{virtual_service_name}-in-to-#{app_name}-8000",
        'namespace' => env_name,
        'labels' => standard_labels
      },
      'spec' => {
        'podSelector' => {
          'matchLabels' => {
            'app.kubernetes.io/instance' => standard_labels['app.kubernetes.io/instance']
          }
        },
        'policyTypes' => [
          'Ingress'
        ],
        'ingress' => [{
          'from' => filters,
          'ports' => [{
            'protocol' => 'TCP',
            'port' => 8000
          }]
        }]
      }
    }
  end

  def create_egress_network_policy(virtual_service_env, virtual_service_name, app_name, env_name, standard_labels, ports, egresses)
    {
      'apiVersion' => 'networking.k8s.io/v1',
      'kind' => 'NetworkPolicy',
      'metadata' => {
        'name' => "allow-#{app_name}-out-to-#{virtual_service_env}-#{virtual_service_name}-#{ports}",
        'namespace' => env_name,
        'labels' => standard_labels
      },
      'spec' => {
        'podSelector' => {
          'matchLabels' => {
            'app.kubernetes.io/instance' => standard_labels['app.kubernetes.io/instance']
          }
        },
        'policyTypes' => [
          'Egress'
        ],
        'egress' => egresses
      }
    }
  end
end
