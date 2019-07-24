require 'stackbuilder/stacks/namespace'
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
    [{ :port => 8000, :fqdns => [vip_fqdn(:prod, fabric)] }]
  end

  def config_params(_dependant, fabric, _dependent_instance)
    if respond_to? :vip_fqdn
      fail("app_service requires application") if application.nil?
      { "#{application.downcase}.url" => "http://#{vip_fqdn(:prod, fabric)}:8000" }
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
    def initialize(template, vars, hiera_provider)
      super(template)
      vars.each { |k, v| instance_variable_set("@#{k}", v) }
      @vars = vars
      @hiera_provider = hiera_provider
    end

    def hiera(key, default = nil)
      @hiera_provider.lookup(@vars, key, default)
    end

    def render
      result(binding)
    end
  end

  def to_k8s(app_deployer, dns_resolver, hiera_provider)
    output = super
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

    erb_vars = {
      'domain' => domain,
      'hostname' => children.first.hostname,
      'application' => application,
      'stackname' => @stack.name,
      'environment' => @environment.name,
      'group' => group,
      'site' => site
    }

    standard_labels = {
      'app.kubernetes.io/name' => app_name,
      'app.kubernetes.io/instance' => instance_name_of(self),
      'app.kubernetes.io/component' => 'app_service',
      'app.kubernetes.io/version' => app_version,
      'app.kubernetes.io/managed-by' => 'stacks'
    }

    output << generate_k8s_config_map(hiera_provider, erb_vars, application, app_name, group, site, fabric, standard_labels)
    output << generate_k8s_service(dns_resolver, app_name, standard_labels)
    output << generate_k8s_deployment(app_name, app_version, standard_labels)
    output += generate_k8s_network_policies(dns_resolver, fabric, standard_labels)
    output
  end

  private

  def instance_name_of(service)
    "#{service.environment.name}-#{service.stack.name}-#{service.application.downcase}"
  end

  def generate_k8s_config_map(hiera_provider, erb_vars, application, app_name, group, site, fabric, standard_labels)
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
        'config.properties' => <<EOC
port=8000

log.directory=/var/log/#{application}/#{@environment.name}-#{application}-#{group}
log.tags=["env:#{@environment.name}", "app:#{application}", "instance:#{group}"]

graphite.enabled=true
graphite.host=#{site}-mon-001.mgmt.#{site}.net.local
graphite.port=2013
graphite.prefix=#{app_name}.k8s_#{@environment.name}_#{site}
graphite.period=10#{generate_dependency_config(fabric)}#{"\n\n" + ConfigERB.new(appconfig, erb_vars, hiera_provider).render unless appconfig.nil?}
EOC
      }
    }
  end

  def generate_dependency_config(fabric)
    config_params = dependency_config(fabric, children.first)
    return '' if config_params.empty?

    "\n\n" + config_params.map do |k, v|
      "#{k}=#{v}"
    end.join("\n")
  end

  def generate_k8s_service(dns_resolver, app_name, standard_labels)
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
          'app.kubernetes.io/name' => app_name
        },
        'ports' => [{
          'name' => 'app',
          'protocol' => 'TCP',
          'port' => 8000,
          'targetPort' => 8000
        }],
        'loadBalancerIP' => dns_resolver.lookup(vip_fqdn('prod', children.first.fabric)).to_s
      }
    }
  end

  def generate_k8s_deployment(app_name, app_version, standard_labels)
    {
      'apiVersion' => 'apps/v1',
      'kind' => 'Deployment',
      'metadata' => {
        'name' => app_name,
        'namespace' => @environment.name,
        'labels' => {
          'stack' => @stack.name,
          'machineset' => @name,
        }.merge(standard_labels)
      },
      'spec' => {
        'selector' => {
          'matchLabels' => {
            'app.kubernetes.io/name' => app_name
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
            'labels' => standard_labels
          },
          'spec' => {
            'containers' => [{
              'image' => "repo.net.local:8080/#{app_name}:#{app_version}",
              'name' => app_name,
              'args' => [
                'java',
                '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5000',
                '-jar',
                '/app/app.jar',
                'config.properties'
              ],
              'ports' => [{
                'containerPort' => 8000,
                'name' => app_name
              }],
              'volumeMounts' => [{
                'name' => 'config-volume',
                'mountPath' => '/app/config.properties',
                'subPath' => 'config.properties'
              }],
              'readinessProbe' => {
                'periodSeconds' => 2,
                'httpGet' => {
                  'path' => '/info/ready',
                  'port' => 8000
                }
              }
            }],
            'volumes' => [{
              'name' => 'config-volume',
              'configMap' => {
                'name' => app_name + '-config'
              }
            }]
          }
        }
      }
    }
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
        virtual_service_instance_fqdns = dependant_instance_fqdns(children.first.location, [@environment.primary_network])
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
            'machineset' => @name,
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
          e[:fqdns].each do |fqdn|
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
            'machineset' => @name,
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
