require 'stackbuilder/stacks/factory'
require 'test_classes'
require 'spec_helper'

describe 'kubernetes' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:failing_app_deployer) { TestAppDeployer.new(nil) }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e1-x-vip.space.net.local' => '3.1.4.1',
                          'e1-app1-001.space.net.local' => '3.1.4.2',
                          'e1-app1-002.space.net.local' => '3.1.4.3',
                          'e1-app2-vip.space.net.local' => '3.1.4.4',
                          'e1-app1-vip.space.net.local' => '3.1.4.5',
                          'e1-nonk8sapp-001.space.net.local' => '3.1.4.14',
                          'space-kube-apiserver-vip.mgmt.space.net.local' => '3.1.4.12',
                          'space-kvm-001.space.net.local' => '10.30.0.252',
                          'space-kvm-005.space.net.local' => '10.30.0.251',
                          'space-kvm-010.space.net.local' => '10.30.0.250',
                          'e1-ntp-vip.space.net.local' => '10.30.1.234'
                         )
  end
  let(:hiera_provider) do
    TestHieraProvider.new(
      'secrety/looking/thing' => 'ENC[GPG,hQIMAyhja+HHo',
      'networking/space/prod/range' => '10.30.0.0/16',
      'kubernetes/masters/space' => ['space-kvm-001.space.net.local', 'space-kvm-005.space.net.local', 'space-kvm-010.space.net.local']
    )
  end

  def network_policies_for(factory, env, stack, service)
    machine_sets = factory.inventory.find_environment(env).definitions[stack].k8s_machinesets
    machine_set = machine_sets[service]

    machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).flat_map(&:resources).select do |policy|
      policy['kind'] == "NetworkPolicy"
    end
  end

  def k8s_resource(set, kind)
    set.to_k8s(app_deployer, dns_resolver, hiera_provider).flat_map(&:resources).find { |s| s['kind'] == kind }
  end

  describe 'base service' do
    describe 'to_k8s method' do
      let(:factory) do
        eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => { 'e1' => true } do
              self.application = 'test'
              self.startup_alert_threshold = '10s'
              self.alerts_channel = 'test'
              self.maintainers = [person('Testers')]
              self.description = 'Test Description'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
      end
      let(:set) do
        factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      end
      it 'generates deployment resources' do
        expected_deployment = {
          'apiVersion' => 'apps/v1',
          'kind' => 'Deployment',
          "metadata" => {
            "name" => "x-blue-app",
            "namespace" => "e1",
            "labels" => {
              "app.kubernetes.io/managed-by" => "stacks",
              "stack" => "mystack",
              "machineset" => "x",
              "group" => "blue",
              "app.kubernetes.io/instance" => "blue",
              "app.kubernetes.io/part-of" => "x",
              "app.kubernetes.io/component" => "base_service",
              "application" => "test",
              "app.kubernetes.io/name" => "test",
              "app.kubernetes.io/version" => "1.2.3"
            },
            "annotations" => {
              "configmap.reloader.stakater.com/reload" => "x-blue-app",
              "secret.reloader.stakater.com/reload" => "x-blue-app",
              "maintainers" => "[{\"type\":\"Individual\",\"name\":\"Testers\"}]",
              "description" => "Test Description"
            }
          },
          'spec' => {
            "selector" => {
              "matchLabels" => {
                "machineset" => "x",
                "group" => "blue",
                "app.kubernetes.io/component" => "base_service",
                "participation" => "enabled"
              }
            },
            "strategy" => {
              "type" => "RollingUpdate",
              "rollingUpdate" => {
                "maxUnavailable" => 1,
                "maxSurge" => 0
              }
            },
            "progressDeadlineSeconds" => 10,
            "replicas" => 2,
            "template" => {
              "metadata" => {
                "labels" => {
                  "participation" => "enabled",
                  "app.kubernetes.io/managed-by" => "stacks",
                  "stack" => "mystack",
                  "machineset" => "x",
                  "group" => "blue",
                  "app.kubernetes.io/instance" => "blue",
                  "app.kubernetes.io/part-of" => "x",
                  "app.kubernetes.io/component" => "base_service",
                  "application" => "test",
                  "app.kubernetes.io/name" => "test",
                  "app.kubernetes.io/version" => "1.2.3"
                },
                "annotations" => {
                  "seccomp.security.alpha.kubernetes.io/pod" => "runtime/default",
                  "maintainers" => "[{\"type\":\"Individual\",\"name\":\"Testers\"}]",
                  "description" => "Test Description"
                }
              },
              "spec" => {
                "affinity" => {
                  "podAntiAffinity" => {
                    "preferredDuringSchedulingIgnoredDuringExecution" => [{
                      "podAffinityTerm" => {
                        "labelSelector" => {
                          "matchLabels" => {
                            "machineset" => "x",
                            "group" => "blue",
                            "app.kubernetes.io/component" => "base_service"
                          }
                        },
                        "topologyKey" => "kubernetes.io/hostname"
                      },
                      "weight" => 100
                    }]
                  }
                },
                "automountServiceAccountToken" => false,
                "containers" => [{
                  "securityContext" => {
                    "readOnlyRootFilesystem" => true,
                    "allowPrivilegeEscalation" => false,
                    "capabilities" => {
                      "drop" => ["ALL"]
                    }
                  },
                  "image" => "repo.net.local:8080/timgroup/test:1.2.3",
                  "name" => "test",
                  "resources" => {
                    "limits" => {
                      "memory" => "65536Ki"
                    },
                    "requests" => {
                      "memory" => "65536Ki"
                    }
                  },
                  "ports" => [],
                  "volumeMounts" => [{
                    "name" => "tmp-volume",
                    "mountPath" => "/tmp"
                  }]
                }],
                "volumes" => [{
                  "name" => "tmp-volume",
                  "emptyDir" => {}
                }]
              }
            }
          }
        }
        expect(k8s_resource(set, 'Deployment')).to eql(expected_deployment)
      end

      it 'generates PodDisruptionBudget resources' do
        expected_pod_disruption_budget = {
          'apiVersion' => 'policy/v1beta1',
          'kind' => 'PodDisruptionBudget',
          'metadata' => {
            'name' => 'x-blue-app',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'base_service'
            }
          },
          'spec' => {
            'maxUnavailable' => 1,
            'selector' => {
              'matchLabels' => {
                'machineset' => 'x',
                'group' => 'blue',
                'app.kubernetes.io/component' => 'base_service'
              }
            }
          }
        }
        expect(k8s_resource(set, 'PodDisruptionBudget')).to eql(expected_pod_disruption_budget)
      end

      it 'generates resources in a sensible order' do
        k8s_resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider).first.resources
        k8s_resources.group_by { |r| r['metadata']['labels']['app.kubernetes.io/component'] }.each do |_component, resources|
          ordering = {}
          resources.each_with_index do |s, index|
            ordering[s['kind']] = index
          end
          if %w(Service Deployment).all? { |k| ordering.key? k }
            expect(ordering['Service']).to be < ordering['Deployment']
          end
          if %w(ConfigMap Deployment).all? { |k| ordering.key? k }
            expect(ordering['ConfigMap']).to be < ordering['Deployment']
          end
        end
      end
    end

    describe 'to_k8s method generation of kubernetes service resources' do
      # I'm unsure whther doing this is actually a valid service resource?
      it 'generates a service resource with an empty port configuration if @ports is overriden' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => { 'e1' => true } do
              self.application = 'test'
              self.startup_alert_threshold = '10s'
              self.alerts_channel = 'test'
              self.maintainers = [person('Testers')]
              self.description = 'Test Description'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end

        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        expected_service = {
          'apiVersion' => 'v1',
          'kind' => 'Service',
          'metadata' => {
            'name' => 'x-blue-app',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'base_service'
            }
          },
          'spec' => {
            'type' => 'ClusterIP',
            'selector' => {
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/component' => 'base_service',
              'participation' => 'enabled'
            },
            'ports' => []
          }
        }
        expect(k8s_resource(set, 'Service')).to eql(expected_service)
      end

      it 'generates a service resource with the correct ports when @ports is overridden' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => { 'e1' => true } do
              self.application = 'test'
              self.startup_alert_threshold = '10s'
              self.alerts_channel = 'test'
              self.maintainers = [person('Testers')]
              self.description = 'Test Description'
              self.ports = {
                'ntp' => {
                  'port' => 123,
                  'service_port' => 123,
                  'protocol' => 'udp'
                }
              }
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end

        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        expected_service = {
          'apiVersion' => 'v1',
          'kind' => 'Service',
          'metadata' => {
            'name' => 'x-blue-app',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'base_service'
            }
          },
          'spec' => {
            'type' => 'ClusterIP',
            'selector' => {
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/component' => 'base_service',
              'participation' => 'enabled'
            },
            'ports' => [
              { "name" => "ntp", "port" => 123, "protocol" => "UDP", "targetPort" => 123 }
            ]
          }
        }
        expect(k8s_resource(set, 'Service')).to eql(expected_service)
      end
    end

    describe 'to_k8s method generation of configmap resources' do
      it 'doesn\'t generate a configmap by default' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => { 'e1' => true } do
              self.application = 'test'
              self.startup_alert_threshold = '10s'
              self.alerts_channel = 'test'
              self.maintainers = [person('Testers')]
              self.description = 'Test Description'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        expect(k8s_resource(set, 'ConfigMap')).to be_nil
      end

      it 'puts appconfig into the configmap if one is specified' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => { 'e1' => true } do
              self.application = 'test'
              self.startup_alert_threshold = '10s'
              self.alerts_channel = 'test'
              self.maintainers = [person('Testers')]
              self.description = 'Test Description'
              self.appconfig = "appconfig = test line"
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        expected_configmap = {
          "apiVersion" => "v1",
          "kind" => "ConfigMap",
          "metadata" => {
            "name" => "x-blue-app",
            "namespace" => "e1",
            "labels" => {
              "app.kubernetes.io/managed-by" => "stacks",
              "stack" => "mystack", "machineset" => "x",
              "group" => "blue",
              "app.kubernetes.io/instance" => "blue",
              "app.kubernetes.io/part-of" => "x",
              "app.kubernetes.io/component" => "base_service"
            }
          },
          "data" => {
            "config.properties" => "appconfig = test line"
          }
        }
        expect(k8s_resource(set, 'ConfigMap')).to eql expected_configmap
      end
    end

    describe 'to_k8s method creates Ingress resources' do
      it 'does not create ingress resources when there are no dependencies external to the cluster' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)
        ingress_resources = resources.flat_map(&:resources).select { |r| r['metadata']['labels']['app.kubernetes.io/component'] == 'ingress' }
        expect(ingress_resources).to be_empty
      end

      xit 'creates ingress resources for TCP services' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.ports = {
                'ssh' => {
                  'port' => 22,
                  'service_port' => 22,
                  'protocol' => 'tcp'
                }
              }

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']

        expected_ingress = {
          'apiVersion' => 'traefik.containo.us/v1alpha1',
          'kind' => 'IngressRouteTCP',
          'metadata' => {
            'name' => 'x-blue-app',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'app_service'
            },
            'annotations' => {
              'kubernetes.io/ingress.class' => 'traefik-x-blue'
            }
          },
          'spec' => {
            "entryPoints" => ["ssh"],
            "routes" => [
              { "services" => [
                { "name" => "x-blue-app", "port" => 22, "kind" => "Service" }
              ] }
            ]
          }
        }

        expect(k8s_resource(set, 'IngressRouteTCP')).to eql(expected_ingress)
      end

      it 'creates ingress resources for UDP services' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.ports = {
                'ntp' => {
                  'port' => 123,
                  'service_port' => 123,
                  'protocol' => 'udp'
                }
              }

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']

        expected_ingress = {
          'apiVersion' => 'traefik.containo.us/v1alpha1',
          'kind' => 'IngressRouteUDP',
          'metadata' => {
            'name' => 'x-blue-app',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'base_service'
            },
            'annotations' => {
              'kubernetes.io/ingress.class' => 'traefik-x-blue'
            }
          },
          'spec' => {
            "entryPoints" => ["ntp"],
            "routes" => [
              { "services" => [
                { "name" => "x-blue-app", "port" => 123, "kind" => "Service" }
              ] }
            ]
          }
        }

        expect(k8s_resource(set, 'IngressRouteUDP')).to eql(expected_ingress)
      end

      it 'creates a deployment resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = {
                'ntp' => {
                  'port' => 123,
                  'service_port' => 123,
                  'protocol' => 'udp'
                }
              }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_deployment = {
          'apiVersion' => 'apps/v1',
          'kind' => 'Deployment',
          'metadata' => {
            'name' => 'x-blue-ing',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress',
              'application' => 'traefik',
              'app.kubernetes.io/name' => 'traefik',
              'app.kubernetes.io/version' => '2.2'
            }
          },
          'spec' => {
            'replicas' => 2,
            'selector' => {
              'matchLabels' => {
                'machineset' => 'x',
                'group' => 'blue',
                'app.kubernetes.io/component' => 'ingress'
              }
            },
            'template' => {
              'metadata' => {
                'labels' => {
                  'app.kubernetes.io/managed-by' => 'stacks',
                  'stack' => 'mystack',
                  'machineset' => 'x',
                  'group' => 'blue',
                  'app.kubernetes.io/instance' => 'blue',
                  'app.kubernetes.io/part-of' => 'x',
                  'app.kubernetes.io/component' => 'ingress',
                  'application' => 'traefik',
                  'app.kubernetes.io/name' => 'traefik',
                  'app.kubernetes.io/version' => '2.2'
                }
              },
              'spec' => {
                'containers' => [
                  {
                    'args' => [
                      '--accesslog',
                      '--ping',
                      '--api.insecure',
                      '--api.dashboard',
                      '--metrics.prometheus',
                      '--log.level=DEBUG',
                      '--entrypoints.traefik.Address=:10254',
                      '--entrypoints.ntp.Address=:8123',
                      '--providers.kubernetesCRD',
                      '--providers.kubernetesCRD.ingressclass=traefik-x-blue',
                      '--providers.kubernetesCRD.namespaces=e1'
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
                      },
                      {
                        'containerPort' => 8123,
                        'name' => 'ntp',
                        'protocol' => 'UDP'
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
                'serviceAccountName' => 'x-blue-ing',
                'terminationGracePeriodSeconds' => 60
              }
            }
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'Deployment' && r['metadata']['name'] == 'x-blue-ing'
        end).to eql(expected_deployment)
      end

      it 'creates a pod disruption budget resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = { 'blah' => { 'port' => 123, 'protocol' => 'udp' } }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_pod_disruption_budget = {
          'apiVersion' => 'policy/v1beta1',
          'kind' => 'PodDisruptionBudget',
          'metadata' => {
            'name' => 'x-blue-ing',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress'
            }
          },
          'spec' => {
            'maxUnavailable' => 1,
            'selector' => {
              'matchLabels' => {
                'machineset' => 'x',
                'group' => 'blue',
                'app.kubernetes.io/component' => 'ingress'
              }
            }
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'PodDisruptionBudget' && r['metadata']['name'] == 'x-blue-ing'
        end).to eql(expected_pod_disruption_budget)
      end

      it 'creates a service resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = {
                'ntp' => {
                  'port' => 123,
                  'service_port' => 123,
                  'protocol' => 'udp'
                }
              }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_service = {
          'apiVersion' => 'v1',
          'kind' => 'Service',
          'metadata' => {
            'name' => 'x-blue-ing',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress'
            },
            'annotations' => {
              'metallb.universe.tf/address-pool' => 'prod-static'
            }
          },
          'spec' => {
            'externalTrafficPolicy' => 'Local',
            'ports' => [
              {
                'name' => 'ntp',
                'port' => 123,
                'protocol' => 'UDP',
                'targetPort' => 'ntp'
              }
            ],
            'selector' => {
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/component' => 'ingress'
            },
            'type' => 'LoadBalancer',
            'loadBalancerIP' => '3.1.4.1'
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'Service' && r['metadata']['name'] == 'x-blue-ing'
        end).to eql(expected_service)
      end

      it 'creates a headless service resource for ingress controllers to expose the traefik admin interface to prometheus' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = { 'blah' => { 'port' => 123, 'protocol' => 'udp' } }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_service = {
          'apiVersion' => 'v1',
          'kind' => 'Service',
          'metadata' => {
            'name' => 'x-blue-ing-mon',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress-monitoring'
            }
          },
          'spec' => {
            'ports' => [
              {
                'name' => 'traefik',
                'port' => 10254,
                'protocol' => 'TCP',
                'targetPort' => 'traefik'
              }
            ],
            'selector' => {
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/component' => 'ingress'
            },
            'clusterIP' => 'None'
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'Service' && r['metadata']['name'] == 'x-blue-ing-mon'
        end).to eql(expected_service)
      end

      it 'creates a role resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = { 'blah' => { 'port' => 123, 'protocol' => 'udp' } }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_role = {
          'kind' => 'Role',
          'apiVersion' => 'rbac.authorization.k8s.io/v1',
          'metadata' => {
            'name' => 'x-blue-ing',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress'
            }
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

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'Role' && r['metadata']['name'] == 'x-blue-ing'
        end).to eql(expected_role)
      end

      it 'creates a serviceaccount resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = { 'blah' => { 'port' => 123, 'protocol' => 'udp' } }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_service_account = {
          'kind' => 'ServiceAccount',
          'apiVersion' => 'v1',
          'metadata' => {
            'name' => 'x-blue-ing',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress'
            }
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'ServiceAccount' && r['metadata']['name'] == 'x-blue-ing'
        end).to eql(expected_service_account)
      end

      it 'creates a role binding resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = { 'blah' => { 'port' => 123, 'protocol' => 'udp' } }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_role_binding = {
          'kind' => 'RoleBinding',
          'apiVersion' => 'rbac.authorization.k8s.io/v1',
          'metadata' => {
            'name' => 'x-blue-ing',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress'
            }
          },
          'roleRef' => {
            'apiGroup' => 'rbac.authorization.k8s.io',
            'kind' => 'Role',
            'name' => 'x-blue-ing'
          },
          'subjects' => [{
            'kind' => 'ServiceAccount',
            'name' => 'x-blue-ing'
          }]
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'RoleBinding' && r['metadata']['name'] == 'x-blue-ing'
        end).to eql(expected_role_binding)
      end

      it 'creates network policies allowing ingress controllers to talk out to the api server' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = { 'blah' => { 'port' => 123, 'protocol' => 'udp' } }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_network_policy = {
          'apiVersion' => 'networking.k8s.io/v1',
          'kind' => 'NetworkPolicy',
          'metadata' => {
            'name' => 'allow-out-to-api-server-65cf5ba',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress'
            }
          },
          'spec' => {
            'egress' => [{
              'to' => [
                {
                  'ipBlock' => {
                    'cidr' => '10.30.0.252/32'
                  }
                },
                {
                  'ipBlock' => {
                    'cidr' => '10.30.0.251/32'
                  }
                },
                {
                  'ipBlock' => {
                    'cidr' => '10.30.0.250/32'
                  }
                }
              ],
              'ports' => [{
                'port' => 6443,
                'protocol' => 'TCP'
              }]
            }],
            'podSelector' => {
              'matchLabels' => {
                'machineset' => 'x',
                'group' => 'blue',
                'app.kubernetes.io/component' => 'ingress'
              }
            },
            'policyTypes' => [
              'Egress'
            ]
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'NetworkPolicy' && r['metadata']['name'] =~ /allow-out-to-api-server-/
        end).to eql(expected_network_policy)
      end

      it 'creates network policies allowing prometheus to monitor the ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.ports = { 'blah' => { 'port' => 123, 'protocol' => 'udp' } }
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 2
              self.startup_alert_threshold = '1h'
            end
            app_service 'nonk8sapp' do
              self.instances = 1
              depend_on 'x', 'e1'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expected_network_policy = {
          'apiVersion' => 'networking.k8s.io/v1',
          'kind' => 'NetworkPolicy',
          'metadata' => {
            'name' => 'allow-in-from-mon-prom-main-1f525ea',
            'namespace' => 'e1',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'stack' => 'mystack',
              'machineset' => 'x',
              'group' => 'blue',
              'app.kubernetes.io/instance' => 'blue',
              'app.kubernetes.io/part-of' => 'x',
              'app.kubernetes.io/component' => 'ingress'
            }
          },
          'spec' => {
            'ingress' => [{
              'from' => [{
                'namespaceSelector' => {
                  'matchLabels' => {
                    'name' => 'monitoring'
                  }
                },
                'podSelector' => {
                  'matchLabels' => {
                    'prometheus' => 'main'
                  }
                }
              }],
              'ports' => [{
                'port' => 'traefik',
                'protocol' => 'TCP'
              }]
            }],
            'podSelector' => {
              'matchLabels' => {
                'machineset' => 'x',
                'group' => 'blue',
                'app.kubernetes.io/component' => 'ingress'
              }
            },
            'policyTypes' => [
              'Ingress'
            ]
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'NetworkPolicy' && r['metadata']['name'] == 'allow-in-from-mon-prom-main-1f525ea'
        end).to eql(expected_network_policy)
      end
    end

    describe 'PrometheusRule' do
      it 'doesn\'t create an alert rule for critical status components' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        prometheus_rule = k8s_resource(set, 'PrometheusRule')

        expect(prometheus_rule['apiVersion']).to eql('monitoring.coreos.com/v1')
        expect(prometheus_rule['metadata']).to eql('labels' => {
                                                     'prometheus' => 'main',
                                                     'role' => 'alert-rules',
                                                     'app.kubernetes.io/managed-by' => 'stacks',
                                                     'stack' => 'mystack',
                                                     'machineset' => 'x',
                                                     'group' => 'blue',
                                                     'app.kubernetes.io/instance' => 'blue',
                                                     'app.kubernetes.io/part-of' => 'x',
                                                     'app.kubernetes.io/component' => 'base_service'
                                                   },
                                                   'name' => 'x-blue-app',
                                                   'namespace' => 'e1')

        expect(prometheus_rule['spec']['groups'].first['name']).to eql('stacks-alerts')
        status_critical_rule = prometheus_rule['spec']['groups'].first['rules'].find do |r|
          r['alert'] == 'StatusCritical'
        end
        expect(status_critical_rule).to be_nil
      end

      it 'creates an alert rule for pods stuck in a crash loop' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        prometheus_rule = k8s_resource(set, 'PrometheusRule')

        expect(prometheus_rule['apiVersion']).to eql('monitoring.coreos.com/v1')
        expect(prometheus_rule['metadata']).to eql('labels' => {
                                                     'prometheus' => 'main',
                                                     'role' => 'alert-rules',
                                                     'app.kubernetes.io/managed-by' => 'stacks',
                                                     'stack' => 'mystack',
                                                     'machineset' => 'x',
                                                     'group' => 'blue',
                                                     'app.kubernetes.io/instance' => 'blue',
                                                     'app.kubernetes.io/part-of' => 'x',
                                                     'app.kubernetes.io/component' => 'base_service'
                                                   },
                                                   'name' => 'x-blue-app',
                                                   'namespace' => 'e1')

        expect(prometheus_rule['spec']['groups'].first['name']).to eql('stacks-alerts')
        rule = prometheus_rule['spec']['groups'].first['rules'].find do |r|
          r['alert'] == 'PodCrashLooping'
        end
        expect(rule).to eql('alert' => 'PodCrashLooping',
                            'expr' => "kube_pod_container_status_last_terminated_reason{namespace='e1', pod=~'^x-blue-app.*'} == 1 and " \
                                              "on(pod, container) rate(kube_pod_container_status_restarts_total[5m]) * 300 > 1",
                            'labels' => {
                              'severity' => 'critical',
                              'alertname' => 'x-blue-app is stuck in a crash loop',
                              'alert_owner_channel' => 'test'
                            },
                            'annotations' => {
                              'message' => 'Pod {{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is restarting ' \
                                '{{ printf "%.2f" $value }} times / 5 minutes.'
                            })
      end

      it 'creates an alert rule for pods failing to retrieve their image' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        prometheus_rule = k8s_resource(set, 'PrometheusRule')

        expect(prometheus_rule['apiVersion']).to eql('monitoring.coreos.com/v1')
        expect(prometheus_rule['metadata']).to eql('labels' => {
                                                     'prometheus' => 'main',
                                                     'role' => 'alert-rules',
                                                     'app.kubernetes.io/managed-by' => 'stacks',
                                                     'stack' => 'mystack',
                                                     'machineset' => 'x',
                                                     'group' => 'blue',
                                                     'app.kubernetes.io/instance' => 'blue',
                                                     'app.kubernetes.io/part-of' => 'x',
                                                     'app.kubernetes.io/component' => 'base_service'
                                                   },
                                                   'name' => 'x-blue-app',
                                                   'namespace' => 'e1')

        expect(prometheus_rule['spec']['groups'].first['name']).to eql('stacks-alerts')
        rule = prometheus_rule['spec']['groups'].first['rules'].find do |r|
          r['alert'] == 'ImageRetrievalFailure'
        end
        expect(rule).to eql('alert' => 'ImageRetrievalFailure',
                            'expr' => "kube_pod_container_status_waiting_reason{reason=~'^(ErrImagePull|ImagePullBackOff|InvalidImageName)$', " \
                              "namespace='e1', pod=~'^x-blue-app.*'} == 1",
                            'labels' => {
                              'severity' => 'warning',
                              'alertname' => 'x-blue-app is failing to retrieve the requested image',
                              'alert_owner_channel' => 'test'
                            },
                            'annotations' => {
                              'message' => 'Pod {{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is failing to retrieve ' \
                                'the requested image.'
                            })
      end

      it 'creates an alert rule for readiness probe failures occurring post-startup' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'

              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'PrometheusRule'
        end['spec']['groups'].first['rules'].find do |rule|
          rule['alert'] == 'FailedReadinessProbe'
        end).to eql('alert' => 'FailedReadinessProbe',
                    'expr' => '(((time() - kube_pod_start_time{pod=~".*x-blue-app.*"}) > 3600) '\
                        'and on(pod) (rate(prober_probe_total{probe_type="Readiness",result="failed",pod=~"^x-blue-app.*"}[1m]) > 0))',
                    'labels' => {
                      'severity' => 'warning',
                      'alertname' => 'x-blue-app failed readiness probe when deployment not in progress',
                      'alert_owner_channel' => 'test'
                    },
                    'annotations' => {
                      'message' => '{{ $labels.namespace }}/{{ $labels.pod }} has failed readiness probe when deployment not in progress',
                      'status_page_url' => "https://go.timgroup.com/insight/space/proxy/e1/{{ $labels.pod }}/info/status"
                    })
      end

      it 'allows turning off the readiness probe failure alert' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'

              self.startup_alert_threshold = '1h'
              self.monitor_readiness_probe = false
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'PrometheusRule'
        end['spec']['groups'].first['rules'].find do |rule|
          rule['alert'] == 'FailedReadinessProbe'
        end).to eql(nil)
      end

      it 'creates an alert rule for missing replicas in a deployment' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'

              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'PrometheusRule'
        end['spec']['groups'].first['rules'].find do |rule|
          rule['alert'] == 'DeploymentReplicasMismatch'
        end).to eql('alert' => 'DeploymentReplicasMismatch',
                    'expr' => "kube_deployment_spec_replicas{job='kube-state-metrics', namespace='e1', deployment='x-blue-app'} != " \
                      "kube_deployment_status_replicas_available{job='kube-state-metrics', namespace='e1', deployment='x-blue-app'}",
                    'for' => '1h',
                    'labels' => {
                      'severity' => 'warning',
                      'alertname' => 'x-blue-app is missing replicas',
                      'alert_owner_channel' => 'test'
                    },
                    'annotations' => {
                      'message' => 'Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has not ' \
                        'matched the expected number of replicas for longer than the startup_alert_threshold (1h).'
                    })
      end

      it 'sends component alerts to the specified alerting channel' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.alerts_channel = "testing-alerts"
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        status_critical_rule = k8s_resource(set, 'PrometheusRule')['spec']['groups'].first['rules'].find do |r|
          r['alert'] == 'DeploymentReplicasMismatch'
        end
        expect(status_critical_rule['labels']['alert_owner_channel']).to eql('testing-alerts')
      end
    end

    describe 'instance control' do
      it 'controls the number of replicas in the primary site' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = 3000
              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        expect(k8s_resource(set, 'Deployment')['spec']['replicas']).to eql(3000)
      end

      it 'controls the number of replicas in the specific sites' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.instances = {
                'space' => 2,
                'earth' => 3
              }
              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space', :secondary_site => 'earth' do
            instantiate_stack "mystack"
          end
        end
        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

        expect(resources.find { |r| r.site == 'space' }.resources.find { |r| r['kind'] == 'Deployment' }['spec']['replicas']).to eql(2)
        expect(resources.find { |r| r.site == 'earth' }.resources.find { |r| r['kind'] == 'Deployment' }['spec']['replicas']).to eql(3)
      end
    end

    it 'generates config from app-defined template' do
      factory = eval_stacks do
        stack "mystack" do
          base_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'MyApplication'
            self.appconfig = <<EOL
  site=<%= @site %>
EOL
            self.startup_alert_threshold = '1h'
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect(k8s_resource(set, 'ConfigMap')['data']['config.properties']).to match(/site=space/)
    end

    #    it 'tracks secrets needed from hiera' do
    #      factory = eval_stacks do
    #        stack "mystack" do
    #          base_service "x", :kubernetes => true do
    #            self.maintainers = [person('Testers')]
    #            self.description = 'Testing'
    #            self.alerts_channel = 'test'
    #
    #            self.application = 'MyApplication'
    #            self.appconfig = <<EOL
    #  secret=<%= secret('my/very/secret.data') %>
    #  array_secret=<%= secret('my/very/secret.array', 0) %>
    # EOL
    #            self.startup_alert_threshold = '1h'
    #          end
    #        end
    #        env "e1", :primary_site => 'space' do
    #          instantiate_stack "mystack"
    #        end
    #      end
    #
    #      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
    #
    #      expect(k8s_resource(set, 'ConfigMap')['data']['config.properties']).
    #        to match(/secret={SECRET:my_very_secret_data.*array_secret={SECRET:my_very_secret_array_0/m)
    #
    #      expect(k8s_resource(set, 'Deployment')['spec']['template']['spec']['initContainers'].
    #             first['env'].
    #             find { |e| e['name'] =~ /data/ }).
    #        to eql(
    #          'name' => 'SECRET_my_very_secret_data',
    #          'valueFrom' => {
    #            'secretKeyRef' => {
    #              'name' => 'x-blue-app',
    #              'key' => 'my_very_secret_data'
    #            }
    #          })
    #
    #      expect(k8s_resource(set, 'Deployment')['spec']['template']['spec']['initContainers'].
    #             first['env'].
    #             find { |e| e['name'] =~ /array/ }).
    #        to eql(
    #          'name' => 'SECRET_my_very_secret_array_0',
    #          'valueFrom' => {
    #            'secretKeyRef' => {
    #              'name' => 'x-blue-app',
    #              'key' => 'my_very_secret_array_0'
    #            }
    #          })
    #
    #      k8s = set.to_k8s(app_deployer, dns_resolver, hiera_provider)
    #      expect(k8s.first.secrets).to eql(
    #        'my/very/secret.data' => 'my_very_secret_data',
    #        'my/very/secret.array' => 'my_very_secret_array_0')
    #    end

    it 'blows up when hiera function used for an encrypted value' do
      factory = eval_stacks do
        stack "mystack" do
          base_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.startup_alert_threshold = '1h'

            self.application = 'MyApplication'
            self.appconfig = <<EOL
  secret=<%= hiera('secrety/looking/thing') %>
EOL
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end

      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect { set.to_k8s(app_deployer, dns_resolver, hiera_provider) }.
        to raise_error(/The hiera value for .* is encrypted/)
    end

    it 'fails when the app version cannot be found' do
      factory = eval_stacks do
        stack "mystack" do
          base_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'MyApplication'
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect { set.to_k8s(failing_app_deployer, dns_resolver, hiera_provider) }.
        to raise_error(RuntimeError, /Version not found in cmdb/)
    end

    it 'does not mess with lbs for k8s things' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'MyApplication'
          end
        end
        stack 'loadbalancer_service' do
          loadbalancer_service do
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
          instantiate_stack 'loadbalancer_service'
        end
      end
      lb_first_machine_def = factory.inventory.find_environment("e1").
                             definitions['loadbalancer_service'].children.first.children.first
      expect(lb_first_machine_def.to_enc["role::loadbalancer"]["virtual_servers"].size).to eq(0)
    end

    it 'sets up a service account when use_service_account is specified and adds it to the deployment resource' do
      factory = eval_stacks do
        stack "mystack" do
          base_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.application = 'MyApplication'
            self.startup_alert_threshold = '1h'

            use_service_account
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      pod_spec = k8s_resource(set, 'Deployment')['spec']['template']['spec']
      service_account = k8s_resource(set, 'ServiceAccount')

      expect(pod_spec['automountServiceAccountToken']).to eq(true)
      expect(pod_spec['serviceAccountName']).to eq('x-blue-app')

      expect(service_account).to eq(
        'apiVersion' => 'v1',
        'kind' => 'ServiceAccount',
        'metadata' => {
          'namespace' => 'e1',
          'name' => 'x-blue-app',
          'labels' => {
            'app.kubernetes.io/managed-by' => 'stacks',
            'stack' => 'mystack',
            'machineset' => 'x',
            'group' => 'blue',
            'app.kubernetes.io/instance' => 'blue',
            'app.kubernetes.io/part-of' => 'x',
            'app.kubernetes.io/component' => 'base_service'
          }
        }
      )
    end

    it 'creates the correct network polices to allow the pods to talk to the Kubernetes api' do
      factory = eval_stacks do
        stack "mystack" do
          base_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.application = 'MyApplication'
            self.startup_alert_threshold = '1h'

            use_service_account
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end

      network_policies = network_policies_for(factory, 'e1', 'mystack', 'x')

      expect(network_policies.size).to eq(2)
      network_policy = network_policies.last
      expect(network_policy['metadata']['name']).to eql('allow-out-to-space-kubernetes-api-dcbf68f')
      expect(network_policy['metadata']['namespace']).to eql('e1')
      expect(network_policy['metadata']['labels']).to eql(
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => 'mystack',
        'machineset' => 'x',
        'group' => 'blue',
        'app.kubernetes.io/instance' => 'blue',
        'app.kubernetes.io/part-of' => 'x',
        'app.kubernetes.io/component' => 'base_service'
      )
      expect(network_policy['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'x',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(network_policy['spec']['policyTypes']).to eql(['Egress'])
      expect(network_policy['spec']['egress'].size).to eq(1)
      expect(network_policy['spec']['egress'].first['to'].size).to eq(1)
      expect(network_policy['spec']['egress'].first['ports'].size).to eq(1)
      expect(network_policy['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.12/32' })
      expect(network_policy['spec']['egress'].first['ports'].first['protocol']).to eql('TCP')
      expect(network_policy['spec']['egress'].first['ports'].first['port']).to eq(6443)
    end

    describe 'limits (max) and requests (min)' do
      it 'bases container limits and requests on the max heap memory' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'

              self.application = 'MyApplication'
              self.memory_limit = '100G'
              self.startup_alert_threshold = '1h'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end

        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        app_container = k8s_resource(set, 'Deployment')['spec']['template']['spec']['containers'].first

        expect(app_container['resources']['limits']['memory']).to eq('104857600Ki')
        expect(app_container['resources']['requests']['memory']).to eq('104857600Ki')
      end

      it 'allows setting a milli cpu limit and request' do
        factory = eval_stacks do
          stack "mystack" do
            base_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'
              self.alerts_channel = 'test'
              self.application = 'MyApplication'
              self.startup_alert_threshold = '1h'

              self.cpu_request = '100m'
              self.cpu_limit = '500m'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end

        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        resources = k8s_resource(set, 'Deployment')['spec']['template']['spec']['containers'][0]['resources']
        expect(resources['requests']['cpu']).to eq('100m')
        expect(resources['limits']['cpu']).to eq('500m')
      end
    end

    describe 'metadata' do
      describe 'maintainers' do
        it 'allows maintainers to be people' do
          factory = eval_stacks do
            stack "mystack" do
              base_service "x", :kubernetes => true do
                self.application = 'MyApplication'
                self.maintainers = [
                  person('Andrew Parker', :slack => '@aparker', :email => 'andy.parker@timgroup.com'),
                  person('Uncontactable'),
                  person('Joe Maille', :email => 'joe@example.com')]
                self.description = 'testing'
                self.alerts_channel = 'test'
                self.startup_alert_threshold = '1h'
              end
            end
            env "e1", :primary_site => 'space' do
              instantiate_stack "mystack"
            end
          end

          set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
          annotations = k8s_resource(set, 'Deployment')['metadata']['annotations']

          expect(JSON.load(annotations['maintainers'])).to eq([
            { 'type' => 'Individual', 'name' => 'Andrew Parker', 'slack' => '@aparker', 'email' => 'andy.parker@timgroup.com' },
            { 'type' => 'Individual', 'name' => 'Uncontactable' },
            { 'type' => 'Individual', 'name' => 'Joe Maille', 'email' => 'joe@example.com' }
          ])
        end

        it 'allows maintainers to be slack channels' do
          factory = eval_stacks do
            stack "mystack" do
              base_service "x", :kubernetes => true do
                self.application = 'MyApplication'
                self.maintainers = [slack('#technology')]
                self.description = 'testing'
                self.alerts_channel = 'test'
                self.startup_alert_threshold = '1h'
              end
            end
            env "e1", :primary_site => 'space' do
              instantiate_stack "mystack"
            end
          end

          set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
          annotations = k8s_resource(set, 'Deployment')['metadata']['annotations']

          expect(JSON.load(annotations['maintainers'])).to eq([{ 'type' => 'Group', 'slack_channel' => '#technology' }])
        end

        it 'is required' do
          factory = eval_stacks do
            stack "mystack" do
              base_service "x", :kubernetes => true do
                self.application = 'MyApplication'
                self.description = 'testing'
                self.alerts_channel = 'test'
              end
            end
            env "e1", :primary_site => 'space' do
              instantiate_stack "mystack"
            end
          end

          expect do
            factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x'].to_k8s(app_deployer, dns_resolver, hiera_provider)
          end.to raise_error(/base_service 'x' in 'e1' requires maintainers \(set self\.maintainers\)/)
        end
      end

      describe 'description' do
        it 'provides a description of the service' do
          factory = eval_stacks do
            stack "mystack" do
              base_service "x", :kubernetes => true do
                self.maintainers = [person('Testers')]
                self.application = 'MyApplication'

                self.description = "This application is useful for testing stacks"
                self.alerts_channel = 'test'
                self.startup_alert_threshold = '1h'
              end
            end
            env "e1", :primary_site => 'space' do
              instantiate_stack "mystack"
            end
          end

          set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
          annotations = k8s_resource(set, 'Deployment')['metadata']['annotations']

          expect(annotations['description']).to eq("This application is useful for testing stacks")
        end

        it 'is required' do
          factory = eval_stacks do
            stack "mystack" do
              base_service "x", :kubernetes => true do
                self.application = 'MyApplication'
                self.maintainers = [person('Testers')]
              end
            end
            env "e1", :primary_site => 'space' do
              instantiate_stack "mystack"
            end
          end

          expect do
            factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x'].to_k8s(app_deployer, dns_resolver, hiera_provider)
          end.to raise_error(/base_service 'x' in 'e1' requires description \(set self\.description\)/)
        end
      end
    end
  end

  describe 'dependencies' do
    it 'only connects dependant instances in the same site, when requested' do
      factory = eval_stacks do
        stack 'testing' do
          base_service 'depends_on_everything', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'mars' => 1
            }

            self.application = 'application'
            self.startup_alert_threshold = '1h'

            depend_on 'just_an_app', 'e1', :same_site
          end
          base_service 'just_an_app', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'io' => 1,
              'mars' => 1
            }

            self.application = 'application'
            self.startup_alert_threshold = '1h'
          end
        end
        env 'e1', :primary_site => 'io', :secondary_site => 'mars' do
          instantiate_stack 'testing'
        end
      end

      dns = AllocatingDnsResolver.new

      machine_sets = factory.inventory.find_environment('e1').definitions['testing'].k8s_machinesets
      depends_on_everything_resources = machine_sets['depends_on_everything'].to_k8s(app_deployer, dns, hiera_provider)
      just_an_app_resources = machine_sets['just_an_app'].to_k8s(app_deployer, dns, hiera_provider)

      just_an_app_in_io = just_an_app_resources.find { |r| r.site == 'io' }
      just_an_app_in_mars = just_an_app_resources.find { |r| r.site == 'mars' }

      expect(just_an_app_in_io.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'].include?('allow-in-from-e1-depends_on_e')
      end).to be_nil
      expect(just_an_app_in_mars.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'].include?('allow-in-from-e1-depends_on_e')
      end).not_to be_nil

      expect(depends_on_everything_resources.first.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'].include?('allow-out-to-e1-just_an_app')
      end).not_to be_nil
    end

    it 'can depend on all kubernetes instances in the same site' do
      factory = eval_stacks do
        stack 'testing' do
          app_service 'depends_on_everything', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'mars' => 1
            }

            self.application = 'application'
            self.startup_alert_threshold = '1h'

            depend_on :all, :all, :same_site
          end
          app_service 'just_an_app', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'io' => 1,
              'mars' => 1
            }

            self.application = 'just_an_app'
            self.startup_alert_threshold = '1h'
          end
          app_service 'another_app', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'io' => 1,
              'mars' => 1
            }

            self.application = 'another_app'
            self.startup_alert_threshold = '1h'
          end
        end
        env 'e1', :primary_site => 'io', :secondary_site => 'mars' do
          instantiate_stack 'testing'
        end
      end

      dns = AllocatingDnsResolver.new

      machine_sets = factory.inventory.find_environment('e1').definitions['testing'].k8s_machinesets
      depends_on_everything_resources = machine_sets['depends_on_everything'].to_k8s(app_deployer, dns, hiera_provider)
      just_an_app_resources = machine_sets['just_an_app'].to_k8s(app_deployer, dns, hiera_provider)

      just_an_app_in_io = just_an_app_resources.find { |r| r.site == 'io' }
      just_an_app_in_mars = just_an_app_resources.find { |r| r.site == 'mars' }

      expect(just_an_app_in_io.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'].include?('allow-in-from-e1-depends_on_e')
      end).to be_nil
      expect(just_an_app_in_mars.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'].include?('allow-in-from-e1-depends_on_e')
      end).not_to be_nil

      expect(depends_on_everything_resources.first.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'].include?('allow-out-to-all')
      end).not_to be_nil

      config = depends_on_everything_resources.first.resources.find { |r| r['kind'] == 'ConfigMap' }['data']['config.properties']
      expect(config).to match(/just_an_app\.url=/)
      expect(config).to match(/another_app\.url=/)
    end

    it 'can depend on all kubernetes app_services in the same site' do
      factory = eval_stacks do
        stack 'testing' do
          base_service 'depends_on_app_services', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'mars' => 1
            }

            self.application = 'application'
            self.startup_alert_threshold = '1h'

            depend_on_labels({ 'app.kubernetes.io/component' => 'app_service' }, :all, :same_site)
          end
          app_service 'just_an_app', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'io' => 1,
              'mars' => 1
            }

            self.application = 'just_an_app'
            self.startup_alert_threshold = '1h'
          end
          base_service 'another_base_app', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'io' => 1,
              'mars' => 1
            }

            self.application = 'another_app'
            self.startup_alert_threshold = '1h'
          end
        end
        env 'e1', :primary_site => 'io', :secondary_site => 'mars' do
          instantiate_stack 'testing'
        end
      end

      dns = AllocatingDnsResolver.new
      e1 = factory.inventory.find_environment('e1')
      machine_sets = e1.definitions['testing'].k8s_machinesets
      depends_on_app_services_ms = machine_sets['depends_on_app_services']
      depends_on_app_services_ms_deps = depends_on_app_services_ms.dependencies
      expect(depends_on_app_services_ms_deps.size).to be_eql(1)
      targets = depends_on_app_services_ms_deps.first.resolve_targets(e1)
      expect(targets.size).to be_eql(1)
      expect(targets.first.name).to be_eql('just_an_app')

      just_an_app_resources = machine_sets['just_an_app'].to_k8s(app_deployer, dns, hiera_provider)

      just_an_app_in_io = just_an_app_resources.find { |r| r.site == 'io' }
      just_an_app_in_mars = just_an_app_resources.find { |r| r.site == 'mars' }

      just_an_app_in_io_network_policy = just_an_app_in_io.resources.select do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'] =~ /allow-in-from-e1-depends_on_a-/
      end
      expect(just_an_app_in_io_network_policy.size).to be(0)

      just_an_app_in_mars_network_policy = just_an_app_in_mars.resources.select do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'] =~ /allow-in-from-e1-depends_on_a-/
      end

      expect(just_an_app_in_mars_network_policy.size).to be(1)
      spec = just_an_app_in_mars_network_policy.first['spec']
      expect(spec['ingress']).to be_eql([{
                                          "from" => [{
                                            "podSelector" => {
                                              "matchLabels" => {
                                                "app.kubernetes.io/component" => "app_service"
                                              }
                                            },
                                            "namespaceSelector" => {
                                              "matchLabels" => {
                                                "name" => "e1"
                                              }
                                            }
                                          }],
                                          "ports" => [{
                                            "protocol" => "TCP",
                                            "port" => "app"
                                          }]
                                        }])

      another_base_app_resources = machine_sets['another_base_app'].to_k8s(app_deployer, dns, hiera_provider)

      another_base_app_in_io = another_base_app_resources.find { |r| r.site == 'io' }
      another_base_app_in_mars = another_base_app_resources.find { |r| r.site == 'mars' }

      another_base_app_in_io_network_policy = another_base_app_in_io.resources.select do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'] =~ /allow-in-from-e1-depends_on_a-/
      end
      expect(another_base_app_in_io_network_policy.size).to be_eql(0)

      another_base_app_in_mars_network_policy = another_base_app_in_mars.resources.select do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'] =~ /allow-in-from-e1-depends_on_a-/
      end
      expect(another_base_app_in_mars_network_policy.size).to be_eql(0)
    end

    it 'only connects dependant vms in the same site, when requested' do
      factory = eval_stacks do
        stack 'testing' do
          app_service 'target', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.instances = {
              'mars' => 1
            }

            self.application = 'application'
            self.startup_alert_threshold = '1h'
          end
          app_service 'source' do
            self.instances = {
              'io' => 1,
              'mars' => 1
            }

            self.application = 'application'
            depend_on 'target', 'e1', :same_site
          end
        end
        env 'e1', :primary_site => 'io', :secondary_site => 'mars' do
          instantiate_stack 'testing'
        end
      end

      dns = AllocatingDnsResolver.new

      machine_sets = factory.inventory.find_environment('e1').definitions['testing'].k8s_machinesets
      depends_on_everything_resources = machine_sets['target'].to_k8s(app_deployer, dns, hiera_provider)

      policy = depends_on_everything_resources.first.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'].include?('allow-in-from-e1-source')
      end

      expect(policy['spec']['ingress'][0]['from']).to eq([
        { 'ipBlock' => { 'cidr' => dns.lookup('e1-source-001.mars.net.local').to_s + '/32' } }
      ])
    end

    it 'should create the correct network policies for a service in kubernetes when another non kubernetes service depends on it' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1' do
            depend_on 'app2'
          end

          base_service 'app2', :kubernetes => true do
            self.ports = {
              'ntp' => {
                'port' => 123,
                'protocol' => 'udp'
              }
            }
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'app2'
            self.startup_alert_threshold = '1h'
          end
        end

        env "e1", :primary_site => "space" do
          instantiate_stack "test_app_servers"
        end
      end

      machine_sets = factory.inventory.find_environment('e1').definitions['test_app_servers'].k8s_machinesets
      app2_machine_set = machine_sets['app2']
      expect(app2_machine_set.dependant_instance_fqdns(:primary_site, [app2_machine_set.environment.primary_network])).to eql([
        "e1-app1-001.space.net.local",
        "e1-app1-002.space.net.local"
      ])

      network_policies = app2_machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).
                         flat_map(&:resources).
                         select { |s| s['kind'] == "NetworkPolicy" }

      expect(network_policies.size).to eq(6)

      ingress_controller_ingress_policy = network_policies.find do |r|
        r['metadata']['name'].include?('allow-in-from-e1-app1')
      end

      expect(ingress_controller_ingress_policy).not_to be_nil
      expect(ingress_controller_ingress_policy['metadata']['namespace']).to eql('e1')
      expect(ingress_controller_ingress_policy['metadata']['labels']).to eql(
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/instance' => 'blue',
        'app.kubernetes.io/part-of' => 'app2',
        'app.kubernetes.io/component' => 'ingress'
      )
      expect(ingress_controller_ingress_policy['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'ingress'
      )
      expect(ingress_controller_ingress_policy['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress_controller_ingress_policy['spec']['ingress'].size).to eq(1)
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['from'].size).to eq(2)
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['ports'].size).to eq(1)
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.2/32' })
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.3/32' })
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['ports'].first['protocol']).to eql('UDP')
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['ports'].first['port']).to eq('ntp')

      ingress_controller_egress_policy = network_policies.find do |r|
        r['metadata']['name'].include?('allow-out-to-e1-app2')
      end

      expect(ingress_controller_egress_policy).not_to be_nil
      expect(ingress_controller_egress_policy['metadata']['namespace']).to eql('e1')
      expect(ingress_controller_egress_policy['metadata']['labels']).to eql(
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/instance' => 'blue',
        'app.kubernetes.io/part-of' => 'app2',
        'app.kubernetes.io/component' => 'ingress'
      )
      expect(ingress_controller_egress_policy['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'ingress'
      )
      expect(ingress_controller_egress_policy['spec']['policyTypes']).to eql(['Egress'])
      expect(ingress_controller_egress_policy['spec']['egress'].size).to eq(1)
      expect(ingress_controller_egress_policy['spec']['egress'].first['to'].size).to eq(1)
      expect(ingress_controller_egress_policy['spec']['egress'].first['ports'].size).to eq(1)
      expect(ingress_controller_egress_policy['spec']['egress'].first['to'].first['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(ingress_controller_egress_policy['spec']['egress'].first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(ingress_controller_egress_policy['spec']['egress'].first['ports'].first['protocol']).to eql('UDP')
      expect(ingress_controller_egress_policy['spec']['egress'].first['ports'].first['port']).to eq('ntp')

      app_ingress_policy = network_policies.find do |r|
        r['metadata']['name'].include?('allow-in-from-e1-app2')
      end

      expect(app_ingress_policy).not_to be_nil
      expect(app_ingress_policy['metadata']['namespace']).to eql('e1')
      expect(app_ingress_policy['metadata']['labels']).to eql(
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/instance' => 'blue',
        'app.kubernetes.io/part-of' => 'app2',
        'app.kubernetes.io/component' => 'base_service'
      )
      expect(app_ingress_policy['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'base_service'
      )
      expect(app_ingress_policy['spec']['policyTypes']).to eql(['Ingress'])
      expect(app_ingress_policy['spec']['ingress'].size).to eq(1)
      expect(app_ingress_policy['spec']['ingress'].first['from'].size).to eq(1)
      expect(app_ingress_policy['spec']['ingress'].first['ports'].size).to eq(1)
      expect(app_ingress_policy['spec']['ingress'].first['from'].first['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'ingress'
      )
      expect(app_ingress_policy['spec']['ingress'].first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(app_ingress_policy['spec']['ingress'].first['ports'].first['protocol']).to eql('UDP')
      expect(app_ingress_policy['spec']['ingress'].first['ports'].first['port']).to eq('ntp')
    end

    it 'should create the correct egress network policies for a service in kubernetes when that service depends on another non kubernetes service' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1' do
            self.application = 'app1'
          end

          base_service 'app2', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'app2'
            self.startup_alert_threshold = '1h'
            depend_on 'app1'
          end
        end

        env "e1", :primary_site => "space" do
          instantiate_stack "test_app_servers"
        end
      end

      machine_sets = factory.inventory.find_environment('e1').definitions['test_app_servers'].k8s_machinesets
      app2_machine_set = machine_sets['app2']

      network_policies = app2_machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).
                         flat_map(&:resources).
                         select { |s| s['kind'] == "NetworkPolicy" }

      expect(network_policies.size).to eq(2)
      expect(network_policies.first['metadata']['name']).to eql('allow-out-to-e1-app1-23bb767')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['labels']).to eql(
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/instance' => 'blue',
        'app.kubernetes.io/part-of' => 'app2',
        'app.kubernetes.io/component' => 'base_service'
      )
      expect(network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(network_policies.first['spec']['egress'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['to'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['ports'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.5/32' })
      expect(network_policies.first['spec']['egress'].first['ports'].first['protocol']).to eql('TCP')
      expect(network_policies.first['spec']['egress'].first['ports'].first['port']).to eq(8000)
    end

    it 'should create the correct network policies for two services in kubernetes in the same environment when one service depends on the other' do
      factory = eval_stacks do
        stack "test_app_servers" do
          base_service 'app1', :kubernetes => true do
            self.ports = {
              'ntp' => {
                'port' => 123,
                'protocol' => 'udp'
              }
            }
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'app1'
            self.startup_alert_threshold = '1h'
          end

          base_service 'app2', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'app2'
            self.startup_alert_threshold = '1h'
            depend_on 'app1'
          end
        end

        env "e1", :primary_site => "space" do
          instantiate_stack "test_app_servers"
        end
      end

      app1_network_policies = network_policies_for(factory, 'e1', 'test_app_servers', 'app1')
      app2_network_policies = network_policies_for(factory, 'e1', 'test_app_servers', 'app2')

      ingress = app1_network_policies.first['spec']['ingress']
      expect(app1_network_policies.size).to eq(2)
      expect(app1_network_policies.first['metadata']['name']).to match(/allow-in-from-e1-app2-/)
      expect(app1_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app1_network_policies.first['metadata']['labels']).to eql(
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => 'test_app_servers',
        'machineset' => 'app1',
        'group' => 'blue',
        'app.kubernetes.io/instance' => 'blue',
        'app.kubernetes.io/part-of' => 'app1',
        'app.kubernetes.io/component' => 'base_service'
      )
      expect(app1_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'app1',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'base_service'
      )
      expect(app1_network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to eq(1)
      expect(ingress.first['from'].size).to eq(1)
      expect(ingress.first['ports'].size).to eq(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(ingress.first['ports'].first['protocol']).to eql('UDP')
      expect(ingress.first['ports'].first['port']).to eq('ntp')

      egress = app2_network_policies.first['spec']['egress']
      expect(app2_network_policies.size).to eq(2)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-out-to-e1-app1-ea24b2a')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app2_network_policies.first['metadata']['labels']).to eql(
        'app.kubernetes.io/managed-by' => 'stacks',
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/instance' => 'blue',
        'app.kubernetes.io/part-of' => 'app2',
        'app.kubernetes.io/component' => 'base_service'
      )
      expect(app2_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(app2_network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to eq(1)
      expect(egress.first['to'].size).to eq(1)
      expect(egress.first['ports'].size).to eq(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']).to eql(
        'machineset' => 'app1',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(egress.first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to eq('app')
    end

    it 'should not create an egress policy to allow the init container to talk to nexus is @artifact_from_nexus is false' do
      factory = eval_stacks do
        stack "test_app_servers" do
          base_service 'app1', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'app1'
            self.startup_alert_threshold = '1h'
          end
        end

        env "e1", :primary_site => "space" do
          instantiate_stack "test_app_servers"
        end
      end

      network_policies = network_policies_for(factory, 'e1', 'test_app_servers', 'app1')

      expect(network_policies.size).to eq(1)
      expect(network_policies.select do |policy|
        policy['metadata']['name'] =~ /allow-out-to-off-nexus-/
      end).to be_empty
    end

    it 'should create the correct network policies for two services in \
kubernetes in different environments in the same site when one service \
depends on the other' do
      factory = eval_stacks do
        stack "test_app_server1" do
          base_service 'app1', :kubernetes => true do
            self.ports = {
              'ntp' => {
                'port' => '123',
                'protocol' => 'udp'
              }
            }
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'app1'
            self.startup_alert_threshold = '1h'
          end
        end
        stack "test_app_server2" do
          base_service 'app2', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'app2'
            self.startup_alert_threshold = '1h'
            depend_on 'app1', 'e1'
          end
        end

        env "e1", :primary_site => "space" do
          instantiate_stack "test_app_server1"
        end
        env "e2", :primary_site => "space" do
          instantiate_stack "test_app_server2"
        end
      end

      app1_network_policies = network_policies_for(factory, 'e1', 'test_app_server1', 'app1')
      app2_network_policies = network_policies_for(factory, 'e2', 'test_app_server2', 'app2')

      ingress = app1_network_policies.first['spec']['ingress']
      expect(app1_network_policies.size).to eq(2)
      expect(app1_network_policies.first['metadata']['name']).to match(/allow-in-from-e2-app2-/)
      expect(app1_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app1_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'app1',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'base_service'
      )
      expect(app1_network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to eq(1)
      expect(ingress.first['from'].size).to eq(1)
      expect(ingress.first['ports'].size).to eq(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e2')
      expect(ingress.first['ports'].first['protocol']).to eql('UDP')
      expect(ingress.first['ports'].first['port']).to eq('ntp')

      egress = app2_network_policies.first['spec']['egress']
      expect(app2_network_policies.size).to eq(2)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-out-to-e1-app1-ea24b2a')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e2')
      expect(app2_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'machineset' => 'app2',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(app2_network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to eq(1)
      expect(egress.first['to'].size).to eq(1)
      expect(egress.first['ports'].size).to eq(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']).to eql(
        'machineset' => 'app1',
        'group' => 'blue',
        'app.kubernetes.io/component' => 'app_service'
      )
      expect(egress.first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to eq('app')
    end

    it 'should fail when dependency does not provide endpoints' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'app'
            self.startup_alert_threshold = '1h'
            depend_on 'logstash-receiver'
          end
          logstash_receiver 'logstash-receiver' do
          end
        end
        env "e1", :primary_site => "space" do
          instantiate_stack "test_app_servers"
        end
      end

      machine_sets = factory.inventory.find_environment('e1').definitions['test_app_servers'].k8s_machinesets
      machine_set = machine_sets['app1']
      expect { machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider) }.to raise_error(
        RuntimeError,
        match(/not supported for k8s - endpoints method is not implemented/))
    end

    it 'allows an environment to depend on a service' do
      factory = eval_stacks do
        stack "test_app_servers" do
          base_service 'ntp', :kubernetes => true do
            self.ports = {
              'ntp' => {
                'port' => 123,
                'protocol' => 'udp'
              }
            }
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'

            self.application = 'ntp'
            self.startup_alert_threshold = '1m'
          end
        end
        env "e1", :primary_site => "space" do
          depend_on 'ntp'
          instantiate_stack "test_app_servers"
        end
      end
      app1_network_policies = network_policies_for(factory, 'e1', 'test_app_servers', 'ntp')
      allow_env_policies = app1_network_policies.select { |policy| policy['metadata']['name'] =~ /allow-in-from-e1-e1-/ }
      expect(allow_env_policies.size).to be(1)
      allow_env_policy = allow_env_policies.first

      expect(allow_env_policy['spec']['podSelector']['matchLabels']).to eq("machineset" => "ntp",
                                                                           "group" => "blue",
                                                                           "app.kubernetes.io/component" => "ingress")
      expect(allow_env_policy['spec']['ingress'].first['from']).to eq [{ "ipBlock" => { "cidr" => "10.30.0.0/16" } }]
      expect(allow_env_policy['spec']['ingress'].first['ports']).to eq [{ "protocol" => "UDP", "port" => "ntp" }]
    end
  end

  it 'raises an error if ports contains both names \'app\' and \'http\'' do
    factory = eval_stacks do
      stack "mystack" do
        base_service "x", :kubernetes => { 'e1' => true } do
          self.ports = {
            'app' => { 'port' => 8000 },
            'http' => { 'port' => 80 }
          }
          self.application = 'ntp'
          self.startup_alert_threshold = '10s'
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end

    expect do
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      set.to_k8s(app_deployer, dns_resolver, hiera_provider).first.resources
    end.to raise_error('base_service \'x\' in \'e1\' defines ports named both \'app\' and \'http\'. This is not possible at the moment ' \
      'because in some places \'app\' is fudged to be \'http\' to avoid changing lots of things in one go.')
  end

  it 'raises an error if @ports is empty and something else depends on the service' do
    factory = eval_stacks do
      stack "mystack" do
        base_service "x", :kubernetes => { 'e1' => true } do
          self.maintainers = [person('Testers')]
          self.description = 'Testing'
          self.alerts_channel = 'test'
          self.application = 'ntp'
          self.startup_alert_threshold = '10s'
        end
        app_service 'nonk8sapp' do
          self.instances = 1
          depend_on 'x', 'e1'
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    expect do
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      set.to_k8s(app_deployer, dns_resolver, hiera_provider).first.resources
    end.to raise_error('base_service \'x\' in \'e1\' doesn\'t define @ports but is depended on by another service')
  end

  it 'allows you to adjust the capabilites of the app container' do
    factory = eval_stacks do
      stack "mystack" do
        base_service "x", :kubernetes => { 'e1' => true } do
          self.maintainers = [person('Testers')]
          self.description = 'Testing'
          self.alerts_channel = 'test'
          self.application = 'ntp'
          self.startup_alert_threshold = '10s'
          self.capabilities = ['NET_BIND_SERVICE']
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
    expected_caps = { "drop" => ["ALL"], "add" => ["NET_BIND_SERVICE"] }
    expect(k8s_resource(set, 'Deployment')['spec']['template']['spec']['containers'].first['securityContext']['capabilities']).to eql(expected_caps)
  end

  it 'allows you to create outgoing network policies' do
    factory = eval_stacks do
      stack "mystack" do
        base_service "x", :kubernetes => { 'e1' => true } do
          self.maintainers = [person('Testers')]
          self.description = 'Testing'
          self.alerts_channel = 'test'
          self.application = 'ntp'
          self.startup_alert_threshold = '10s'
          self.capabilities = ['NET_BIND_SERVICE']
          allow_outbound_to 'external-ntp-servers', '0.0.0.0/0', [123], 'UDP'
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
    network_policy = k8s_resource(set, 'NetworkPolicy')
    expect(network_policy['metadata']['name']).to match(/allow-out-to-external-ntp-servers-/)
    expect(network_policy['spec']['podSelector']['matchLabels']).to eq("machineset" => "x",
                                                                       "group" => "blue",
                                                                       "app.kubernetes.io/component" => "base_service")
  end
end
