require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/kubernetes_resources'
require 'erb'

module Stacks::Services::AppService
  include Stacks::Services::RabbitMqDependent

  attr_accessor :ajp_port
  attr_accessor :application
  attr_accessor :ehcache
  attr_accessor :idea_positions_exports
  attr_accessor :jvm_args
  attr_accessor :sso_port
  attr_accessor :tomcat_session_replication
  attr_accessor :use_ha_mysql_ordering
  attr_accessor :ha_mysql_ordering_exclude

  attr_accessor :appconfig
  attr_accessor :jvm_heap
  attr_accessor :headspace

  alias_method :database_username, :application
  alias_method :database_username=, :application=

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
    @jvm_heap = '1024M'
    @headspace = 0.1
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
      @hiera_provider.lookup(@vars, key, default)
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
    fail("app_service requires application") if application.nil?
    app_name = application.downcase
    fail('app_service to_k8s doesn\'t know how to deal with multiple groups yet') if @groups.size > 1
    group = @groups.first
    fail('app_service to_k8s doesn\'t know how to deal with multiple sites yet') if @enable_secondary_site || @instances.is_a?(Hash)
    site = @environment.sites.first

    begin
      app_version = app_deployer.query_cmdb_for(:application => application,
                                                :environment => @environment.name,
                                                :group => group)[:target_version]
    rescue
      raise("Version not found in cmdb for application: '#{application}', group: '#{group}' in environment: '#{environment.name}'")
    end

    location = environment.translate_site_symbol(site)
    fabric = environment.options[location]
    domain = "mgmt.#{environment.domain(fabric)}"

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
      'dependencies' => dependency_config(fabric, nil),
      'credentials_selector' => hiera_provider.lookup(hiera_scope, 'stacks/application_credentials_selector', nil)
    }.merge(hiera_scope)

    standard_labels = {
      'app.kubernetes.io/name' => app_name,
      'app.kubernetes.io/instance' => instance_name_of(self),
      'app.kubernetes.io/component' => 'app_service',
      'app.kubernetes.io/version' => app_version,
      'app.kubernetes.io/managed-by' => 'stacks'
    }

    config, used_secrets = generate_app_config(erb_vars, hiera_provider)

    output = super app_deployer, dns_resolver, hiera_provider, standard_labels
    output << generate_k8s_config_map(config, standard_labels)
    output << generate_k8s_service(dns_resolver, standard_labels)
    output << generate_k8s_deployment(standard_labels, used_secrets)
    output += generate_k8s_network_policies(dns_resolver, fabric, standard_labels)
    Stacks::KubernetesResources.new(site, @environment.name, @stack.name, name, standard_labels, output, used_secrets, hiera_scope)
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
    "#{service.environment.name}-#{service.stack.name}-#{service.application.downcase}"
  end

  def generate_app_config(erb_vars, hiera_provider)
    template = <<'EOC'
port=8000

log.directory=/var/log/app
log.tags=["env:<%= @logicalenv %>", "app:<%= @application %>", "instance:<%= @group %>"]

graphite.enabled=true
graphite.host=<%= @site %>-mon-001.mgmt.<%= @site %>.net.local
graphite.port=2013
graphite.prefix=<%= @application.downcase %>.k8s_<%= @logicalenv %>_<%= @site %>
graphite.period=10
<%- if @dependencies.size > 1 -%>
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
        'labels' => {
          'stack' => @stack.name,
          'machineset' => @name
        }.merge(standard_labels)
      },
      'data' => {
        'config.properties' => config
      }
    }
  end

  def generate_k8s_service(dns_resolver, standard_labels)
    app_name = standard_labels['app.kubernetes.io/name']

    {
      'apiVersion' => 'v1',
      'kind' => 'Service',
      'metadata' => {
        'name' => app_name,
        'namespace' => @environment.name,
        'labels' => {
          'stack' => @stack.name,
          'machineset' => @name
        }.merge(standard_labels)
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
        'loadBalancerIP' => dns_resolver.lookup(prod_fqdn(fabric)).to_s
      }
    }
  end

  def generate_k8s_deployment(standard_labels, secrets)
    app_name = standard_labels['app.kubernetes.io/name']
    app_version = standard_labels['app.kubernetes.io/version']
    jvm_args = @jvm_args.is_a?(String) ? @jvm_args.split(' ') : []

    {
      'apiVersion' => 'apps/v1',
      'kind' => 'Deployment',
      'metadata' => {
        'name' => app_name,
        'namespace' => @environment.name,
        'labels' => {
          'stack' => @stack.name,
          'machineset' => @name
        }.merge(standard_labels)
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
        'replicas' => @instances,
        'template' => {
          'metadata' => {
            'labels' => {
              'participation' => 'enabled'
            }.merge(standard_labels)
          },
          'spec' => {
            'initContainers' => [{
              'image' => 'repo.net.local:8080/config-generator:1.0.1',
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
              end,
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
              'image' => "repo.net.local:8080/#{app_name}:#{app_version}",
              'name' => app_name,
              'args' => [
                'java',
                '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5000'
              ] + jvm_args + [
                "-Xmx#{@jvm_heap}",
                '-jar',
                '/app/app.jar',
                '/config/config.properties'
              ],
              'resources' => {
                'limits' => { 'memory' => scale_memory(@jvm_heap, @headspace) + 'i' },
                'requests' => { 'memory' => scale_memory(@jvm_heap, @headspace) + 'i' }
              },
              'ports' => [{
                'containerPort' => 8000,
                'name' => 'http'
              }],
              'volumeMounts' => [{
                'name' => 'config-volume',
                'mountPath' => '/config',
                'readOnly' => true
              }],
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
              }]
          }
        }
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

  def generate_k8s_network_policies(dns_resolver, fabric, standard_labels)
    network_policies = []
    virtual_services_that_depend_on_me.each do |vs|
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

      network_policies << {
        'apiVersion' => 'networking.k8s.io/v1',
        'kind' => 'NetworkPolicy',
        'metadata' => {
          'name' => "allow-#{vs.environment.name}-#{vs.name}-in-to-#{@name}-8000",
          'namespace' => @environment.name,
          'labels' => {
            'stack' => @stack.name,
            'machineset' => @name
          }.merge(standard_labels)
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

    virtual_services_that_i_depend_on(false).each do |vs|
      fail "Dependency '#{vs.name}' is not supported for k8s - endpoints method is not implemented" if !vs.respond_to?(:endpoints)

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
        vs.endpoints(self, fabric).each do |e|
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
      network_policies << {
        'apiVersion' => 'networking.k8s.io/v1',
        'kind' => 'NetworkPolicy',
        'metadata' => {
          'name' => "allow-#{@name}-out-to-#{vs.environment.name}-#{vs.name}-#{vs.endpoints(self, fabric).map { |e| e[:port] }.join('-')}",
          'namespace' => @environment.name,
          'labels' => {
            'stack' => @stack.name,
            'machineset' => @name
          }.merge(standard_labels)
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
    network_policies
  end
end
