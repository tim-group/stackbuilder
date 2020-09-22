require 'stackbuilder/stacks/kubernetes/network_policy_common'

module Stacks::Kubernetes::ResourceSetIngress
  include Stacks::Kubernetes::NetworkPolicyCommon

  ##
  # Classes including this module must define the following instance variables
  #
  # @ports as a hash of hashes detailing the config of each port.
  # {
  #   A string identifier for this port. This can be one of 'app' or 'metrics'.
  #   The 'app' port is what any service will use for its primary
  #   communication. The 'metrics' port is for exposing metrics to Prometheus.
  #   'name' => {
  #     'port' => An Integer defining the port number
  #     'protocol' => Optional string detailing the protocol of this port. Places in the code should default to TCP if this is undefined.
  #     'service_port' => Optional Integer used to create a Kubernetes Service to expose this app outside the cluster
  #   }
  # }
  #
  # And the following functions
  # non_k8s_dependencies_exist?

  private

  ##
  # Generate all new resources required for an ingree
  def ingress_generate_resources(dns_resolver, hiera_provider, hiera_scope, site, \
                                 standard_labels, app_service_labels, app_resources_name, ingress_resources_name)
    return [] unless non_k8s_dependencies_exist?

    masters = hiera_provider.lookup(hiera_scope, "kubernetes/masters/#{site}", [])

    output = []

    ingress_labels = standard_labels.merge('app.kubernetes.io/component' => 'ingress')

    ingress_resources_name = "#{standard_labels['machineset']}-#{standard_labels['group']}-ing"

    output << generate_ingress_resource(app_resources_name, app_resources_name, app_service_labels)
    output << generate_ingress_controller_service_account_resource(ingress_resources_name, ingress_labels)
    output << generate_ingress_controller_role_resource(ingress_resources_name, ingress_labels)
    output << generate_ingress_controller_role_binding_resource(ingress_resources_name, ingress_labels)
    output += generate_ingress_controller_network_policies(ingress_resources_name, ingress_labels, dns_resolver, hiera_provider, hiera_scope, site, masters)
    output << generate_ingress_controller_service_resource(ingress_resources_name, ingress_labels, dns_resolver, site)
    output << generate_ingress_controller_monitoring_service_resource(ingress_resources_name, ingress_labels)
    output << generate_ingress_controller_deployment_resource(ingress_resources_name, ingress_labels)
    output << generate_ingress_pod_disruption_budget_resource(ingress_resources_name, ingress_labels)

    output
  end

  def generate_ingress_resource(name, app_resource_name, labels)
    resource = {
      'metadata' => {
        'name' => name,
        'namespace' => @environment.name,
        'labels' => labels,
        'annotations' => {
          'kubernetes.io/ingress.class' => "traefik-#{labels['machineset']}-#{labels['group']}"
        }
      }
    }

    # TODO: remove the second half of this once everything is transitioned to
    # use 'app' as the port to expose. Also remove the port_name and just use
    # 'app'
    app_port = @ports['app'] || @ports[@ports.keys.first]

    protocol = app_port['protocol'].nil? ? 'tcp' : app_port['protocol']
    case protocol
    when 'tcp'
      resource['apiVersion'] = 'networking.k8s.io/v1beta1'
      resource['kind'] = 'Ingress'
      resource['spec'] = {
        'rules' => [{
          'http' => {
            'paths' => [{
              'path' => '/',
              'backend' => {
                'serviceName' => app_resource_name,
                'servicePort' => app_port['service_port']
              }
            }]
          }
        }]
      }
    when 'udp'
      kind = "IngressRoute#{protocol.upcase}"
      resource['apiVersion'] = 'traefik.containo.us/v1alpha1'
      resource['kind'] = kind
      resource['spec'] = {
        'entryPoints' => [
          'app'
        ],
        'routes' => [{
          'services' => [{
            'name' => app_resource_name,
            'port' => app_port['service_port'],
            'kind' => 'Service'
          }]
        }]
      }
    else
      fail("generate_k8s_ingress doesn't know how to handle port name '#{port_name}' with protocol '#{protocol}'")
    end

    resource
  end

  def generate_ingress_controller_service_account_resource(name, ingress_labels)
    {
      'apiVersion' => 'v1',
      'kind' => 'ServiceAccount',
      'metadata' => {
        'name' => name,
        'namespace' => @environment.name,
        'labels' => ingress_labels
      }
    }
  end

  def generate_ingress_controller_role_resource(name, ingress_labels)
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
          'resources' => %w(secrets services endpoints),
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
        },
        {
          "apiGroups" => [
            "traefik.containo.us"
          ],
          "resources" => %w(middlewares ingressroutes traefikservices ingressroutetcps ingressrouteudps tlsoptions tlsstores),
          "verbs" => %w(get list watch)
        }
      ]
    }
  end

  def generate_ingress_controller_role_binding_resource(name, ingress_labels)
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

  def generate_ingress_controller_network_policies(_name, ingress_labels, dns_resolver, hiera_provider, hiera_scope, site, masters)
    network_policies = []
    # TODO: remove the second half of this once everything is transitioned to
    # use 'app' as the port to expose. Also remove the port_name and just use
    # 'app'
    app_port = @ports['app'] || @ports[@ports.keys.first]

    app_service_match_labels = {
      'machineset' => ingress_labels['machineset'],
      'group' => 'blue',
      'app.kubernetes.io/component' => @custom_service_name
    }
    egresses = [{
      'to' => [
        generate_pod_and_namespace_selector_filter(@environment.name, app_service_match_labels)
      ],
      'ports' => [{
        'protocol' => app_port['protocol'].nil? ? 'TCP' : app_port['protocol'].upcase,
        'port' => 'app'
      }]
    }]
    ingress_match_labels = {
      'machineset' => ingress_labels['machineset'],
      'group' => 'blue',
      'app.kubernetes.io/component' => 'ingress'
    }
    network_policies << create_egress_network_policy("#{@environment.short_name}-#{short_name}", @environment.name,
                                                     ingress_labels, egresses, ingress_match_labels)

    api_server_egresses = [{
      'to' => masters.map do |master|
        {
          'ipBlock' => {
            'cidr' => "#{dns_resolver.lookup(master)}/32"
          }
        }
      end,
      'ports' => [{
        'port' => 6443,
        'protocol' => 'TCP'
      }]
    }]

    network_policies << create_egress_network_policy_for_external_service('api-server', @environment.name, ingress_labels,
                                                                          api_server_egresses, ingress_match_labels)

    dependants.reject { |dep| dep.from.kubernetes }.each do |dep|
      case dep.from
      when Stacks::Environment
        subnet = hiera_provider.lookup(hiera_scope, "networking/#{site}/prod/range")
        fail("For an environment dependency networking/#{site}/prod/range must be defined in hieradata") if subnet.nil?
        filters = [{
          'ipBlock' => {
            'cidr' => subnet
          }
        }]
        network_policies << create_ingress_network_policy_for_external_service(dep.from.short_name, dep.from.short_name,
                                                                               @environment.name, ingress_labels, filters)
      else
        vs = dep.from
        is_same_site = dep.requirement == :same_site
        next if is_same_site && !vs.exists_in_site?(vs.environment, site)

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
    end

    prom_filters = [generate_pod_and_namespace_selector_filter('monitoring', 'prometheus' => 'main')]
    network_policies << create_ingress_network_policy_to_ingress_for_internal_service('mon', 'prom-main',
                                                                                      @environment.name, ingress_labels,
                                                                                      'traefik', prom_filters, 'TCP')

    network_policies
  end

  def generate_ingress_controller_service_resource(name, ingress_labels, dns_resolver, site)
    # TODO: remove the second half of this once everything is transitioned to
    # use 'app' as the port to expose. Also remove the port_name and just use
    # 'app'
    app_port = @ports['app'] || @ports[@ports.keys.first]

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
        'ports' => [{
          'name' => 'app',
          'port' => app_port['service_port'],
          'protocol' => app_port['protocol'].nil? ? 'TCP' : app_port['protocol'].upcase,
          'targetPort' => 'app'
        }]
      }
    }
  end

  def generate_ingress_controller_monitoring_service_resource(name, ingress_labels)
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

  def generate_ingress_controller_deployment_resource(name, ingress_labels)
    ingress_controller_labels = ingress_labels.merge('app.kubernetes.io/name' => 'traefik',
                                                     'application' => 'traefik',
                                                     'app.kubernetes.io/version' => '2.2')

    deployment = {
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
                  "--metrics.prometheus"
                ],
                'image' => 'traefik:v2.2',
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

    container = deployment['spec']['template']['spec']['containers'].first
    container['args'] << "--entrypoints.traefik.Address=:10254"

    # TODO: remove the second half of this once everything is transitioned to
    # use 'app' as the port to expose. Also remove the port_name and just use
    # 'app'
    app_port = @ports['app'] || @ports[@ports.keys.first]

    actual_port = app_port['port'] < 1024 ? 8000 + app_port['port'] : app_port['port']
    # TODO: mpimm - remove when protocol is required
    protocol = app_port['protocol'].nil? ? 'tcp' : app_port['protocol']
    entrypoint = "--entrypoints.app.Address=:#{actual_port}"
    entrypoint += "/udp" if protocol == 'udp'
    container['args'] << entrypoint
    container['ports'] << {
      'containerPort' => actual_port,
      'name' => 'app',
      'protocol' => protocol.upcase
    }

    case protocol
    when 'tcp'
      container['args'] << "--entrypoints.app.forwardedHeaders.trustedIPs=127.0.0.1/32,10.0.0.0/8"
      container['args'] << "--providers.kubernetesingress"
      container['args'] << "--providers.kubernetesingress.ingressclass=traefik-#{ingress_labels['machineset']}-#{ingress_labels['group']}"
      container['args'] << "--providers.kubernetesingress.ingressendpoint.publishedservice=#{@environment.name}/#{name}"
      container['args'] << "--providers.kubernetesingress.namespaces=#{@environment.name}"
    else
      container['args'] << "--providers.kubernetesCRD"
      container['args'] << "--providers.kubernetesCRD.ingressclass=traefik-#{ingress_labels['machineset']}-#{ingress_labels['group']}"
      container['args'] << "--providers.kubernetesCRD.namespaces=#{@environment.name}"
    end

    deployment
  end

  def generate_ingress_pod_disruption_budget_resource(name, ingress_labels)
    {
      'apiVersion' => 'policy/v1beta1',
      'kind' => 'PodDisruptionBudget',
      'metadata' => {
        'name' => name,
        'namespace' => @environment.name,
        'labels' => ingress_labels
      },
      'spec' => {
        'maxUnavailable' => 1,
        'selector' => {
          'matchLabels' => {
            'machineset' => ingress_labels['machineset'],
            'group' => ingress_labels['group'],
            'app.kubernetes.io/component' => ingress_labels['app.kubernetes.io/component']
          }
        }
      }
    }
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

  def create_ingress_network_policy_to_ingress_for_internal_service(virtual_service_env, virtual_service_name,
                                                                    env_name, labels, port, filters, protocol = 'TCP')
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
          'protocol' => protocol,
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

  def create_ingress_network_policy_for_external_service(virtual_service_env, virtual_service_name, env_name, labels, filters)
    # TODO: remove the second half of this once everything is transitioned to
    # use 'app' as the port to expose. Also remove the port_name and just use
    # 'app'
    app_port = @ports['app'] || @ports[@ports.keys.first]

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
          'protocol' => app_port['protocol'].nil? ? 'TCP' : app_port['protocol'].upcase,
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
end
