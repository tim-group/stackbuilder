require 'stackbuilder/stacks/namespace'

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

  def config_params(_dependant, fabric, _dependent_instance)
    if respond_to? :vip_fqdn
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
    if respond_to?(:load_balanced_service?)
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

  def to_k8s(app_deployer, dns_resolver, hiera_provider)
    output = super
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
      app_version = "UNKNOWN"
    end

    output << generate_k8s_config_map(hiera_provider, application, app_name, group, site)
    output << generate_k8s_service(dns_resolver, app_name)
    output << generate_k8s_deployment(app_name, app_version)
    output += generate_k8s_network_policies(dns_resolver)
    output
  end

  private

  def generate_k8s_config_map(hiera_provider, application, app_name, group, site)
    {
      'apiVersion' => 'v1',
      'kind' => 'ConfigMap',
      'metadata' => {
        'name' => app_name + '-config',
        'namespace' => @environment.name,
        'labels' => {
          'stack' => @stack.name,
          'machineset' => @name
        }
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
graphite.period=10#{"\n\n" + ERB.new(@appconfig).result(binding) unless @appconfig.nil?}
EOC
      }
    }
  end

  def generate_k8s_service(dns_resolver, app_name)
    {
      'apiVersion' => 'v1',
      'kind' => 'Service',
      'metadata' => {
        'name' => app_name,
        'namespace' => @environment.name,
        'labels' => {
          'stack' => @stack.name,
          'machineset' => @name
        }
      },
      'spec' => {
        'type' => 'LoadBalancer',
        'selector' => {
          'app' => app_name
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

  def generate_k8s_deployment(app_name, app_version)
    {
      'apiVersion' => 'apps/v1',
      'kind' => 'Deployment',
      'metadata' => {
        'name' => app_name,
        'namespace' => @environment.name,
        'labels' => {
          'stack' => @stack.name,
          'machineset' => @name
        }
      },
      'spec' => {
        'selector' => {
          'matchLabels' => {
            'app' => app_name
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
              'app' => app_name
            }
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
                  'path' => '/info/health',
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

  def generate_k8s_network_policies(dns_resolver)
    network_policies = []
    virtual_services_that_depend_on_me.each do |vs|
      filters = []
      if vs.kubernetes
        filters << {
          'podSelector' => {
            'matchLabels' => {
              'machine_set' => vs.name,
              'stack' => vs.stack.name
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
          'spec' => {
            'podSelector' => {
              'matchLabels' => {
                'machine_set' => @name,
                'stack' => @stack.name
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
      }
    end

    virtual_services_that_i_depend_on.each do |vs|
      filters = []
      if vs.kubernetes
        filters << {
          'podSelector' => {
            'matchLabels' => {
              'machine_set' => vs.name,
              'stack' => vs.stack.name
            }
          },
          'namespaceSelector' => {
            'matchLabels' => {
              'name' => vs.environment.name
            }
          }
        }
      else
        filters << { 'ipBlock' => { 'cidr' => "#{dns_resolver.lookup(vs.vip_fqdn(:prod, children.first.fabric))}/32" } }
      end
      network_policies << {
        'apiVersion' => 'networking.k8s.io/v1',
        'kind' => 'NetworkPolicy',
        'metadata' => {
          'name' => "allow-#{@name}-out-to-#{vs.environment.name}-#{vs.name}-8000",
          'namespace' => @environment.name,
          'spec' => {
            'podSelector' => {
              'matchLabels' => {
                'machine_set' => @name,
                'stack' => @stack.name
              }
            },
            'policyTypes' => [
              'Egress'
            ],
            'egress' => [{
              'to' => filters,
              'ports' => [{
                'protocol' => 'TCP',
                'port' => 8000
              }]
            }]
          }
        }
      }
    end
    network_policies
  end
end
