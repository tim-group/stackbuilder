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
                          'e2-app2-vip.space.net.local' => '3.1.4.6',
                          'e1-mydb-001.space.net.local' => '3.1.4.7',
                          'e1-mydb-002.space.net.local' => '3.1.4.8',
                          'production-sharedproxy-001.space.net.local' => '3.1.4.9',
                          'production-sharedproxy-002.space.net.local' => '3.1.4.10',
                          'production-sharedproxy-001.earth.net.local' => '4.1.4.9',
                          'production-sharedproxy-002.earth.net.local' => '4.1.4.10',
                          'office-nexus-001.mgmt.lon.net.local' => '3.1.4.11',
                          'space-kube-apiserver-vip.mgmt.space.net.local' => '3.1.4.12',
                          'e1-x-vip.earth.net.local' => '3.1.4.13',
                          'e1-nonk8sapp-001.space.net.local' => '3.1.4.14')
  end
  let(:hiera_provider) do
    TestHieraProvider.new(
      'stacks/application_credentials_selector' => 0,
      'secrety/looking/thing' => 'ENC[GPG,hQIMAyhja+HHo')
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

  describe 'resource definitions' do
    it 'defines a Deployment' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'MyApplication'
            self.jvm_args = '-XX:+UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled'
            self.ephemeral_storage_size = '10G'
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expected_deployment = {
        'apiVersion' => 'apps/v1',
        'kind' => 'Deployment',
        'metadata' => {
          'name' => 'myapplication',
          'namespace' => 'e1',
          'labels' => {
            'stack' => 'mystack',
            'machineset' => 'x',
            'app.kubernetes.io/name' => 'myapplication',
            'app.kubernetes.io/instance' => 'e1_-x',
            'app.kubernetes.io/component' => 'app_service',
            'app.kubernetes.io/version' => '1.2.3',
            'app.kubernetes.io/managed-by' => 'stacks'
          },
          'annotations' => {
            'maintainers' => '[{"type":"Individual","name":"Testers"}]',
            'description' => 'Testing',
            'configmap.reloader.stakater.com/reload' => 'myapplication-config',
            'secret.reloader.stakater.com/reload' =>  'myapplication-secret'
          }
        },
        'spec' => {
          'selector' => {
            'matchLabels' => {
              'app.kubernetes.io/instance' => 'e1_-x',
              'participation' => 'enabled'
            }
          },
          'strategy' => {
            'type' => 'RollingUpdate',
            'rollingUpdate' => {
              'maxUnavailable' => 1,
              'maxSurge' => 0
            }
          },
          'replicas' => 2,
          'template' => {
            'metadata' => {
              'labels' => {
                'participation' => 'enabled',
                'app.kubernetes.io/name' => 'myapplication',
                'app.kubernetes.io/instance' => 'e1_-x',
                'app.kubernetes.io/component' => 'app_service',
                'app.kubernetes.io/version' => '1.2.3',
                'app.kubernetes.io/managed-by' => 'stacks',
                'stack' => 'mystack',
                'machineset' => 'x'
              },
              'annotations' => {
                'maintainers' => '[{"type":"Individual","name":"Testers"}]',
                'description' => 'Testing',
                'seccomp.security.alpha.kubernetes.io/pod' => 'runtime/default'
              }
            },
            'spec' => {
              'affinity' => {
                'podAntiAffinity' => {
                  'preferredDuringSchedulingIgnoredDuringExecution' => [{
                    'podAffinityTerm' => {
                      'labelSelector' => {
                        'matchExpressions' => [{
                          'key' => 'app.kubernetes.io/instance',
                          'operator' => 'In',
                          'values' => ['e1_-x']
                        }]
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
                'env' => [
                  {
                    'name' => 'CONTAINER_IMAGE',
                    'value' => 'repo.net.local:8080/timgroup/myapplication:1.2.3'
                  },
                  {
                    'name' => 'APP_JVM_ARGS',
                    'value' => '-XX:+UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled -Xms64M -Xmx64M'
                  },
                  {
                    'name' => 'BASE_JVM_ARGS',
                    'value' => "-Djava.awt.headless=true -Dfile.encoding=UTF-8 -XX:ErrorFile=/var/log/app/error.log \
-XX:HeapDumpPath=/var/log/app -XX:+HeapDumpOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom -Dcom.sun.management.jmxremote \
-Dcom.sun.management.jmxremote.port=5000 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false \
-Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.rmi.port=5000 -Djava.rmi.server.hostname=127.0.0.1"
                  },
                  {
                    'name' => 'GC_JVM_ARGS_JAVA_8',
                    'value' => "-XX:+PrintGC -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -XX:+PrintGCDetails \
-Xloggc:/var/log/app/gc.log -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=25M \
-XX:+PrintGCApplicationStoppedTime"
                  },
                  {
                    'name' => 'GC_JVM_ARGS_JAVA_11',
                    'value' => '-Xlog:gc*,safepoint:/var/log/app/gc.log:time,uptime,level,tags:filecount=10,filesize=26214400'
                  }
                ],
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
                'image' => 'repo.net.local:8080/timgroup/myapplication:1.2.3',
                'name' => 'myapplication',
                'command' => ["/bin/sh"],
                'args' => [
                  '-c',
                  'exec /usr/bin/java $(cat /config/jvm_args) -jar /app/app.jar /config/config.properties'
                ],
                'resources' => {
                  'limits' => {
                    'memory' => '72089Ki',
                    'ephemeral-storage' => '10G'
                  },
                  'requests' => {
                    'memory' => '72089Ki',
                    'ephemeral-storage' => '10G'
                  }
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
                  'configMap' => {
                    'name' => 'myapplication-config'
                  }
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
      expect(k8s_resource(set, 'Deployment')).to eql(expected_deployment)

      expected_service = {
        'apiVersion' => 'v1',
        'kind' => 'Service',
        'metadata' => {
          'name' => 'myapplication',
          'namespace' => 'e1',
          'labels' => {
            'machineset' => 'x',
            'app.kubernetes.io/name' => 'myapplication',
            'app.kubernetes.io/instance' => 'e1_-x',
            'app.kubernetes.io/component' => 'app_service',
            'app.kubernetes.io/version' => '1.2.3',
            'app.kubernetes.io/managed-by' => 'stacks',
            'stack' => 'mystack'
          }
        },
        'spec' => {
          'type' => 'ClusterIP',
          'selector' => {
            'app.kubernetes.io/instance' => 'e1_-x',
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
      expect(k8s_resource(set, 'Service')).to eql(expected_service)

      expected_config_map = {
        'apiVersion' => 'v1',
        'kind' => 'ConfigMap',
        'metadata' => {
          'name' => 'myapplication-config',
          'namespace' => 'e1',
          'labels' => {
            'stack' => 'mystack',
            'machineset' => 'x',
            'app.kubernetes.io/name' => 'myapplication',
            'app.kubernetes.io/instance' => 'e1_-x',
            'app.kubernetes.io/component' => 'app_service',
            'app.kubernetes.io/version' => '1.2.3',
            'app.kubernetes.io/managed-by' => 'stacks'
          }
        },
        'data' => {
          'config.properties' => <<EOL
port=8000

log.directory=/var/log/app
log.tags=["env:e1", "app:MyApplication", "instance:blue"]

graphite.enabled=false
graphite.host=space-mon-001.mgmt.space.net.local
graphite.port=2013
graphite.prefix=myapplication.k8s_e1_space
graphite.period=10
EOL
        }
      }
      expect(k8s_resource(set, 'ConfigMap')).to eql(expected_config_map)

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

    describe 'Service' do
      it 'connects to the vip in the deployment\'s site' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = {
                'space' => 1,
                'earth' => 1
              }
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

        resources_in_space = resources.find { |r| r.site == 'space' }.resources
        ingress_service_resources_in_space = resources_in_space.find do |r|
          r['kind'] == 'Service' && r['metadata']['labels']['app.kubernetes.io/component'] == 'ingress'
        end

        resources_in_earth = resources.find { |r| r.site == 'earth' }.resources
        ingress_service_resources_in_earth = resources_in_earth.find do |r|
          r['kind'] == 'Service' && r['metadata']['labels']['app.kubernetes.io/component'] == 'ingress'
        end

        expect(ingress_service_resources_in_space['spec']['loadBalancerIP']).
          to eql(dns_resolver.lookup('e1-x-vip.space.net.local').to_s)
        expect(ingress_service_resources_in_earth['spec']['loadBalancerIP']).
          to eql(dns_resolver.lookup('e1-x-vip.earth.net.local').to_s)
      end
    end

    describe 'Ingress' do
      it 'does not create ingress resources when there are no dependencies external to the cluster' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 2
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

      it 'creates ingress resources' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 2
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
          'apiVersion' => 'extensions/v1beta1',
          'kind' => 'Ingress',
          'metadata' => {
            'name' => 'e1_-x',
            'namespace' => 'e1',
            'labels' => {
              'stack' => 'mystack',
              'machineset' => 'x',
              'app.kubernetes.io/name' => 'myapplication',
              'app.kubernetes.io/instance' => 'e1_-x',
              'app.kubernetes.io/component' => 'ingress',
              'app.kubernetes.io/version' => '1.2.3',
              'app.kubernetes.io/managed-by' => 'stacks'
            },
            'annotations' => {
              'kubernetes.io/ingress.class' => 'nginx-e1_-x'
            }
          },
          'spec' => {
            'backend' => {
              'serviceName' => 'myapplication',
              'servicePort' => 8000
            }
          }
        }

        expect(k8s_resource(set, 'Ingress')).to eql(expected_ingress)
      end

      it 'creates a deployment resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 2
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
            'name' => 'e1_-x-ingress-controller',
            'namespace' => 'e1',
            'labels' => {
              'stack' => 'mystack',
              'machineset' => 'x',
              'app.kubernetes.io/name' => 'nginx-ingress',
              'app.kubernetes.io/instance' => 'e1_-x-nginx-ingress',
              'app.kubernetes.io/component' => 'ingress',
              'app.kubernetes.io/version' => '0.26.1',
              'app.kubernetes.io/managed-by' => 'stacks'
            }
          },
          'spec' => {
            'replicas' => 2,
            'selector' => {
              'matchLabels' => {
                'app.kubernetes.io/instance' => 'e1_-x-nginx-ingress'
              }
            },
            'template' => {
              'metadata' => {
                'labels' => {
                  'stack' => 'mystack',
                  'machineset' => 'x',
                  'app.kubernetes.io/name' => 'nginx-ingress',
                  'app.kubernetes.io/instance' => 'e1_-x-nginx-ingress',
                  'app.kubernetes.io/component' => 'ingress',
                  'app.kubernetes.io/version' => '0.26.1',
                  'app.kubernetes.io/managed-by' => 'stacks'
                }
              },
              'spec' => {
                'containers' => [
                  {
                    'args' => [
                      '/nginx-ingress-controller',
                      '--configmap=$(POD_NAMESPACE)/myapplication-nginx-config',
                      '--election-id=ingress-controller-leader-e1_-x',
                      '--publish-service=$(POD_NAMESPACE)/myapplication-ingress',
                      '--ingress-class=nginx-e1_-x',
                      '--http-port=8000',
                      '--watch-namespace=e1'
                    ],
                    'env' => [
                      {
                        'name' => 'POD_NAME',
                        'valueFrom' => {
                          'fieldRef' => {
                            'apiVersion' => 'v1',
                            'fieldPath' => 'metadata.name'
                          }
                        }
                      },
                      {
                        'name' => 'POD_NAMESPACE',
                        'valueFrom' => {
                          'fieldRef' => {
                            'apiVersion' => 'v1',
                            'fieldPath' => 'metadata.namespace'
                          }
                        }
                      }
                    ],
                    'image' => 'quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.26.1',
                    'imagePullPolicy' => 'IfNotPresent',
                    'lifecycle' => {
                      'preStop' => {
                        'exec' => {
                          'command' => [
                            '/wait-shutdown'
                          ]
                        }
                      }
                    },
                    'livenessProbe' => {
                      'failureThreshold' => 3,
                      'httpGet' => {
                        'path' => '/healthz',
                        'port' => 10254,
                        'scheme' => 'HTTP'
                      },
                      'initialDelaySeconds' => 10,
                      'periodSeconds' => 10,
                      'successThreshold' => 1,
                      'timeoutSeconds' => 10
                    },
                    'name' => 'nginx-ingress-controller',
                    'ports' => [
                      {
                        'containerPort' => 80,
                        'name' => 'http',
                        'protocol' => 'TCP'
                      }
                    ],
                    'readinessProbe' => {
                      'failureThreshold' => 3,
                      'httpGet' => {
                        'path' => '/healthz',
                        'port' => 10254,
                        'scheme' => 'HTTP'
                      },
                      'periodSeconds' => 10,
                      'successThreshold' => 1,
                      'timeoutSeconds' => 10
                    },
                    # FIXME:                    'resources' => {},
                    'securityContext' => {
                      'runAsUser' => 33
                    },
                    'terminationMessagePath' => '/dev/termination-log',
                    'terminationMessagePolicy' => 'File'
                  }
                ],
                'serviceAccountName' => 'myapplication-ingress',
                'terminationGracePeriodSeconds' => 300
              }
            }
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'Deployment' && r['metadata']['name'] == 'e1_-x-ingress-controller'
        end).to eql(expected_deployment)
      end

      it 'creates a service resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 2
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
            'labels' => {
              'stack' => 'mystack',
              'machineset' => 'x',
              'app.kubernetes.io/name' => 'myapplication-ingress',
              'app.kubernetes.io/instance' => 'e1_-x-myapplication-ingress',
              'app.kubernetes.io/component' => 'ingress',
              'app.kubernetes.io/managed-by' => 'stacks'
            },
            'annotations' => {
              'metallb.universe.tf/address-pool' => 'prod-static'
            },
            'name' => 'myapplication-ingress',
            'namespace' => 'e1'
          },
          'spec' => {
            'externalTrafficPolicy' => 'Local',
            'ports' => [
              {
                'name' => 'http',
                'port' => 80,
                'protocol' => 'TCP',
                'targetPort' => 'http'
              },
              {
                'name' => 'https',
                'port' => 443,
                'protocol' => 'TCP',
                'targetPort' => 'https'
              }
            ],
            'selector' => {
              'app.kubernetes.io/instance' => 'e1_-x-nginx-ingress'
            },
            'type' => 'LoadBalancer',
            'loadBalancerIP' => '3.1.4.1'
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'Service' && r['metadata']['name'] == 'myapplication-ingress'
        end).to eql(expected_service)
      end

      it 'creates a configmap resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 2
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

        expected_configmap = {
          'kind' => 'ConfigMap',
          'apiVersion' => 'v1',
          'metadata' => {
            'name' => 'myapplication-nginx-config',
            'namespace' => 'e1',
            'labels' => {
              'stack' => 'mystack',
              'machineset' => 'x',
              'app.kubernetes.io/name' => 'myapplication-ingress',
              'app.kubernetes.io/instance' => 'e1_-x-myapplication-ingress',
              'app.kubernetes.io/component' => 'ingress',
              'app.kubernetes.io/managed-by' => 'stacks'
            }
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'ConfigMap' && r['metadata']['name'] == 'myapplication-nginx-config'
        end).to eql(expected_configmap)

        expected_configmap = {
          'kind' => 'ConfigMap',
          'apiVersion' => 'v1',
          'metadata' => {
            'name' => 'ingress-controller-leader-e1_-x-nginx-e1_-x',
            'namespace' => 'e1',
            'labels' => {
              'stack' => 'mystack',
              'machineset' => 'x',
              'app.kubernetes.io/name' => 'myapplication-ingress',
              'app.kubernetes.io/instance' => 'e1_-x-myapplication-ingress',
              'app.kubernetes.io/component' => 'ingress',
              'app.kubernetes.io/managed-by' => 'stacks'
            }
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'ConfigMap' && r['metadata']['name'] == 'ingress-controller-leader-e1_-x-nginx-e1_-x'
        end).to eql(expected_configmap)
      end

      it 'creates a role resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 2
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
          'apiVersion' => 'rbac.authorization.k8s.io/v1beta1',
          'metadata' => {
            'name' => 'myapplication-ingress',
            'namespace' => 'e1',
            'labels' => {
              'stack' => 'mystack',
              'machineset' => 'x',
              'app.kubernetes.io/name' => 'myapplication-ingress',
              'app.kubernetes.io/instance' => 'e1_-x-myapplication-ingress',
              'app.kubernetes.io/component' => 'ingress',
              'app.kubernetes.io/managed-by' => 'stacks'
            }
          },
          'rules' => [
            {
              'apiGroups' => [
                ""
              ],
              'resources' => %w(configmaps pods secrets endpoints namespaces),
              'verbs' => %w(get list watch)
            },
            {
              "apiGroups" => [
                ""
              ],
              "resourceNames" => [
                "ingress-controller-leader-e1_-x-nginx-e1_-x"
              ],
              "resources" => [
                "configmaps"
              ],
              "verbs" => %w(get update)
            },
            {
              "apiGroups" => [
                ""
              ],
              "resources" => [
                "endpoints"
              ],
              "verbs" => [
                "get"
              ]
            },
            {
              "apiGroups" => [
                ""
              ],
              "resources" => [
                "services"
              ],
              "verbs" => %w(get list watch)
            },
            {
              "apiGroups" => [
                ""
              ],
              "resources" => [
                "events"
              ],
              "verbs" => %w(create patch)
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

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'Role' && r['metadata']['name'] == 'myapplication-ingress'
        end).to eql(expected_role)
      end

      it 'creates a serviceaccount resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 2
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
            'name' => 'myapplication-ingress',
            'namespace' => 'e1',
            'labels' => {
              'stack' => 'mystack',
              'machineset' => 'x',
              'app.kubernetes.io/name' => 'myapplication-ingress',
              'app.kubernetes.io/instance' => 'e1_-x-myapplication-ingress',
              'app.kubernetes.io/component' => 'ingress',
              'app.kubernetes.io/managed-by' => 'stacks'
            }
          }
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'ServiceAccount' && r['metadata']['name'] == 'myapplication-ingress'
        end).to eql(expected_service_account)
      end

      it 'creates a role binding resource for ingress controllers' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 2
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
          'apiVersion' => 'rbac.authorization.k8s.io/v1beta1',
          'metadata' => {
            'name' => 'myapplication-ingress',
            'namespace' => 'e1',
            'labels' => {
              'stack' => 'mystack',
              'machineset' => 'x',
              'app.kubernetes.io/name' => 'myapplication-ingress',
              'app.kubernetes.io/instance' => 'e1_-x-myapplication-ingress',
              'app.kubernetes.io/component' => 'ingress',
              'app.kubernetes.io/managed-by' => 'stacks'
            }
          },
          'roleRef' => {
            'apiGroup' => 'rbac.authorization.k8s.io',
            'kind' => 'Role',
            'name' => 'myapplication-ingress'
          },
          'subjects' => [{
            'kind' => 'ServiceAccount',
            'name' => 'myapplication-ingress'
          }]
        }

        expect(resources.flat_map(&:resources).find do |r|
          r['kind'] == 'RoleBinding' && r['metadata']['name'] == 'myapplication-ingress'
        end).to eql(expected_role_binding)
      end
    end

    describe 'instance control' do
      it 'controls the number of replicas in the primary site' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = 3000
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
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.instances = {
                'space' => 2,
                'earth' => 3
              }
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

    it 'labels metrics using the site' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'MyApplication'
            self.instances = 1
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect(k8s_resource(set, 'ConfigMap')['data']['config.properties']).to match(/space-mon-001.mgmt.space.net.local/)
    end

    it 'generates config from app-defined template' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'MyApplication'
            self.appconfig = <<EOL
  site=<%= @site %>
EOL
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect(k8s_resource(set, 'ConfigMap')['data']['config.properties']).to match(/site=space/)
    end

    it 'tracks secrets needed from hiera' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'MyApplication'
            self.appconfig = <<EOL
  secret=<%= secret('my/very/secret.data') %>
  array_secret=<%= secret('my/very/secret.array', 0) %>
EOL
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end

      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']

      expect(k8s_resource(set, 'ConfigMap')['data']['config.properties']).
        to match(/secret={SECRET:my_very_secret_data.*array_secret={SECRET:my_very_secret_array_0/m)

      expect(k8s_resource(set, 'Deployment')['spec']['template']['spec']['initContainers'].
             first['env'].
             find { |e| e['name'] =~ /data/ }).
        to eql(
          'name' => 'SECRET_my_very_secret_data',
          'valueFrom' => {
            'secretKeyRef' => {
              'name' => 'myapplication-secret',
              'key' => 'my_very_secret_data'
            }
          })

      expect(k8s_resource(set, 'Deployment')['spec']['template']['spec']['initContainers'].
             first['env'].
             find { |e| e['name'] =~ /array/ }).
        to eql(
          'name' => 'SECRET_my_very_secret_array_0',
          'valueFrom' => {
            'secretKeyRef' => {
              'name' => 'myapplication-secret',
              'key' => 'my_very_secret_array_0'
            }
          })

      k8s = set.to_k8s(app_deployer, dns_resolver, hiera_provider)
      expect(k8s.first.secrets).to eql(
        'my/very/secret.data' => 'my_very_secret_data',
        'my/very/secret.array' => 'my_very_secret_array_0')
    end

    it 'blows up when hiera function used for an encrypted value' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

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

    it 'has config for it\'s db dependencies' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'MyApplication'
            self.short_name = 'myappl'
            depend_on 'mydb'
          end
        end
        stack "my_db" do
          mysql_cluster "mydb" do
            self.role_in_name = false
            self.database_name = 'exampledb'
            self.master_instances = 1
            self.slave_instances = 1
            self.include_master_in_read_only_cluster = false
          end
        end
        env "e1", :primary_site => 'space', :short_name => 'spc' do
          instantiate_stack "mystack"
          instantiate_stack "my_db"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect(k8s_resource(set, 'ConfigMap')['data']['config.properties']).
        to match(/db.exampledb.hostname=e1-mydb-001.space.net.local.*
                  db.exampledb.database=exampledb.*
                  db.exampledb.driver=com.mysql.jdbc.Driver.*
                  db.exampledb.port=3306.*
                  db.exampledb.username=spcmyappl0.*
                  db.exampledb.password=\{SECRET:e1_MyApplication_mysql_passwords_0\}.*
                  db.exampledb.read_only_cluster=e1-mydb-002.space.net.local.*
                 /mx)
    end

    it 'fails when the app version cannot be found' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

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

    it 'connects a service account' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.application = 'MyApplication'

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
      expect(pod_spec['serviceAccountName']).to eq('x')

      expect(service_account).to eq(
        'apiVersion' => 'v1',
        'kind' => 'ServiceAccount',
        'metadata' => {
          'namespace' => 'e1',
          'name' => 'x',
          'labels' => {
            'stack' => 'mystack',
            'machineset' => 'x',
            'app.kubernetes.io/name' => 'myapplication',
            'app.kubernetes.io/instance' => 'e1_-x',
            'app.kubernetes.io/component' => 'app_service',
            'app.kubernetes.io/version' => '1.2.3',
            'app.kubernetes.io/managed-by' => 'stacks'
          }
        }
      )
    end

    it 'creates the correct network polices to allow the pods to talk to the Kubernetes api' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.application = 'MyApplication'

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
      expect(network_policy['metadata']['name']).to eql('allow-x-out-to-space-kubernetes-api-6443')
      expect(network_policy['metadata']['namespace']).to eql('e1')
      expect(network_policy['metadata']['labels']).to eql(
        'stack' => 'mystack',
        'app.kubernetes.io/name' => 'myapplication',
        'app.kubernetes.io/instance' => 'e1_-x',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks',
        'machineset' => 'x'
      )
      expect(network_policy['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-x'
      )
      expect(network_policy['spec']['policyTypes']).to eql(['Egress'])
      expect(network_policy['spec']['egress'].size).to eq(1)
      expect(network_policy['spec']['egress'].first['to'].size).to eq(1)
      expect(network_policy['spec']['egress'].first['ports'].size).to eq(1)
      expect(network_policy['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.12/32' })
      expect(network_policy['spec']['egress'].first['ports'].first['protocol']).to eql('TCP')
      expect(network_policy['spec']['egress'].first['ports'].first['port']).to eq(6443)
    end

    describe 'memory limits (max) and requests (min) ' do
      it 'bases container limits and requests on the max heap memory' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.jvm_heap = '100G'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end

        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        app_container = k8s_resource(set, 'Deployment')['spec']['template']['spec']['containers'].first
        init_container = k8s_resource(set, 'Deployment')['spec']['template']['spec']['initContainers'].first

        expect(app_container['resources']['limits']['memory']).to eq('115343360Ki')
        expect(app_container['resources']['requests']['memory']).to eq('115343360Ki')
        expect(init_container['env'].find { |env_var| env_var['name'] == 'APP_JVM_ARGS' }['value']).to match(/-Xmx100G/)
      end

      it 'controls container limits by reserving headspace computed from the heap size' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.jvm_heap = '100G'
              self.headspace = 0.5
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end

        set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
        app_container = k8s_resource(set, 'Deployment')['spec']['template']['spec']['containers'].first
        init_container = k8s_resource(set, 'Deployment')['spec']['template']['spec']['initContainers'].first

        expect(app_container['resources']['limits']['memory']).to eq('157286400Ki')
        expect(app_container['resources']['requests']['memory']).to eq('157286400Ki')
        expect(init_container['env'].find { |env_var| env_var['name'] == 'APP_JVM_ARGS' }['value']).to match(/-Xmx100G/)
      end
    end

    describe 'metadata' do
      describe 'maintainers' do
        it 'allows maintainers to be people' do
          factory = eval_stacks do
            stack "mystack" do
              app_service "x", :kubernetes => true do
                self.application = 'MyApplication'
                self.maintainers = [
                  person('Andrew Parker', :slack => '@aparker', :email => 'andy.parker@timgroup.com'),
                  person('Uncontactable'),
                  person('Joe Maille', :email => 'joe@example.com')]
                self.description = 'testing'
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
              app_service "x", :kubernetes => true do
                self.application = 'MyApplication'
                self.maintainers = [slack('#technology')]
                self.description = 'testing'
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
              app_service "x", :kubernetes => true do
                self.application = 'MyApplication'
                self.description = 'testing'
              end
            end
            env "e1", :primary_site => 'space' do
              instantiate_stack "mystack"
            end
          end

          expect do
            factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x'].to_k8s(app_deployer, dns_resolver, hiera_provider)
          end.to raise_error(/app_service 'x' in 'e1' requires maintainers \(set self\.maintainers\)/)
        end
      end

      describe 'description' do
        it 'provides a description of the service' do
          factory = eval_stacks do
            stack "mystack" do
              app_service "x", :kubernetes => true do
                self.maintainers = [person('Testers')]
                self.application = 'MyApplication'

                self.description = "This application is useful for testing stacks"
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
              app_service "x", :kubernetes => true do
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
          end.to raise_error(/app_service 'x' in 'e1' requires description \(set self\.description\)/)
        end
      end
    end
  end

  describe 'dependencies' do
    it 'only connects dependant instances in the same site, when requested' do
      factory = eval_stacks do
        stack 'testing' do
          app_service 'depends_on_everything', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.instances = {
              'mars' => 1
            }

            self.application = 'application'

            depend_on 'just_an_app', 'e1', :same_site
          end
          app_service 'just_an_app', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.instances = {
              'io' => 1,
              'mars' => 1
            }

            self.application = 'application'
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
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'] == 'allow-e1-depends_on_e-in-to-just_an_app-8000'
      end).to be_nil
      expect(just_an_app_in_mars.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'] == 'allow-e1-depends_on_e-in-to-just_an_app-8000'
      end).not_to be_nil

      expect(depends_on_everything_resources.first.resources.find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'] == 'allow-depends_on_everything-out-to-e1-just_an_app-8000'
      end).not_to be_nil
    end

    it 'only connects dependant vms in the same site, when requested' do
      factory = eval_stacks do
        stack 'testing' do
          app_service 'target', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.instances = {
              'mars' => 1
            }

            self.application = 'application'
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
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'] == 'allow-e1-source-in-to-target-ingress-http'
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

          app_service 'app2', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app2'
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

      expect(network_policies.size).to eq(5)

      ingress_controller_ingress_policy = network_policies.find do |r|
        r['metadata']['name'] == 'allow-e1-app1-in-to-app2-ingress-http'
      end

      expect(ingress_controller_ingress_policy).not_to be_nil
      expect(ingress_controller_ingress_policy['metadata']['namespace']).to eql('e1')
      expect(ingress_controller_ingress_policy['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2-ingress',
        'app.kubernetes.io/instance' => 'e1_-app2-ingress',
        'app.kubernetes.io/component' => 'ingress',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(ingress_controller_ingress_policy['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app2-nginx-ingress'
      )
      expect(ingress_controller_ingress_policy['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress_controller_ingress_policy['spec']['ingress'].size).to eq(1)
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['from'].size).to eq(2)
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['ports'].size).to eq(1)
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.2/32' })
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.3/32' })
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['ports'].first['protocol']).to eql('TCP')
      expect(ingress_controller_ingress_policy['spec']['ingress'].first['ports'].first['port']).to eq('http')

      ingress_controller_egress_policy = network_policies.find do |r|
        r['metadata']['name'] == 'allow-app2-ingress-out-to-e1-app2-app'
      end

      expect(ingress_controller_egress_policy).not_to be_nil
      expect(ingress_controller_egress_policy['metadata']['namespace']).to eql('e1')
      expect(ingress_controller_egress_policy['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2-ingress',
        'app.kubernetes.io/instance' => 'e1_-app2-ingress',
        'app.kubernetes.io/component' => 'ingress',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(ingress_controller_egress_policy['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app2-nginx-ingress'
      )
      expect(ingress_controller_egress_policy['spec']['policyTypes']).to eql(['Egress'])
      expect(ingress_controller_egress_policy['spec']['egress'].size).to eq(1)
      expect(ingress_controller_egress_policy['spec']['egress'].first['to'].size).to eq(1)
      expect(ingress_controller_egress_policy['spec']['egress'].first['ports'].size).to eq(1)
      expect(ingress_controller_egress_policy['spec']['egress'].first['to'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app2'
      )
      expect(ingress_controller_egress_policy['spec']['egress'].first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(ingress_controller_egress_policy['spec']['egress'].first['ports'].first['protocol']).to eql('TCP')
      expect(ingress_controller_egress_policy['spec']['egress'].first['ports'].first['port']).to eq('app')

      app_ingress_policy = network_policies.find do |r|
        r['metadata']['name'] == 'allow-e1-app2-ingress-in-to-app2-app'
      end

      expect(app_ingress_policy).not_to be_nil
      expect(app_ingress_policy['metadata']['namespace']).to eql('e1')
      expect(app_ingress_policy['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1_-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(app_ingress_policy['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app2'
      )
      expect(app_ingress_policy['spec']['policyTypes']).to eql(['Ingress'])
      expect(app_ingress_policy['spec']['ingress'].size).to eq(1)
      expect(app_ingress_policy['spec']['ingress'].first['from'].size).to eq(1)
      expect(app_ingress_policy['spec']['ingress'].first['ports'].size).to eq(1)
      expect(app_ingress_policy['spec']['ingress'].first['from'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app2-nginx-ingress'
      )
      expect(app_ingress_policy['spec']['ingress'].first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(app_ingress_policy['spec']['ingress'].first['ports'].first['protocol']).to eql('TCP')
      expect(app_ingress_policy['spec']['ingress'].first['ports'].first['port']).to eq('app')
    end

    it 'should create the correct egress network policies for a service in kubernetes when that service depends on another non kubernetes service' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1' do
            self.application = 'app1'
          end

          app_service 'app2', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app2'
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
      expect(network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1_-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app2'
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
          app_service 'app1', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app1'
          end

          app_service 'app2', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app2'
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
      expect(app1_network_policies.size).to eq(3)
      expect(app1_network_policies.first['metadata']['name']).to eql('allow-e1-app2-in-to-app1-8000')
      expect(app1_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app1_network_policies.first['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app1',
        'app.kubernetes.io/name' => 'app1',
        'app.kubernetes.io/instance' => 'e1_-app1',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(app1_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app1'
      )
      expect(app1_network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to eq(1)
      expect(ingress.first['from'].size).to eq(1)
      expect(ingress.first['ports'].size).to eq(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app2'
      )
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(ingress.first['ports'].first['protocol']).to eql('TCP')
      expect(ingress.first['ports'].first['port']).to eq(8000)

      egress = app2_network_policies.first['spec']['egress']
      expect(app2_network_policies.size).to eq(2)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app2_network_policies.first['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1_-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(app2_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app2'
      )
      expect(app2_network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to eq(1)
      expect(egress.first['to'].size).to eq(1)
      expect(egress.first['ports'].size).to eq(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app1'
      )
      expect(egress.first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to eq(8000)
    end

    it 'should create an egress policy to allow the init container to talk to nexus' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app1'
          end
        end

        env "e1", :primary_site => "space" do
          instantiate_stack "test_app_servers"
        end
      end

      network_policies = network_policies_for(factory, 'e1', 'test_app_servers', 'app1')

      expect(network_policies.size).to eq(1)
      expect(network_policies.first['metadata']['name']).to eql('allow-app1-out-to-office-nexus-8080')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app1',
        'app.kubernetes.io/name' => 'app1',
        'app.kubernetes.io/instance' => 'e1_-app1',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app1'
      )
      expect(network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(network_policies.first['spec']['egress'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['to'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['ports'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.11/32' })
      expect(network_policies.first['spec']['egress'].first['ports'].first['protocol']).to eql('TCP')
      expect(network_policies.first['spec']['egress'].first['ports'].first['port']).to eq(8080)
    end

    it 'should create the correct network policies for two services in \
kubernetes in different environments in the same site when one service \
depends on the other' do
      factory = eval_stacks do
        stack "test_app_server1" do
          app_service 'app1', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app1'
          end
        end
        stack "test_app_server2" do
          app_service 'app2', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app2'
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
      expect(app1_network_policies.size).to eq(3)
      expect(app1_network_policies.first['metadata']['name']).to eql('allow-e2-app2-in-to-app1-8000')
      expect(app1_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app1_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app1'
      )
      expect(app1_network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to eq(1)
      expect(ingress.first['from'].size).to eq(1)
      expect(ingress.first['ports'].size).to eq(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e2_-app2'
      )
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e2')
      expect(ingress.first['ports'].first['protocol']).to eql('TCP')
      expect(ingress.first['ports'].first['port']).to eq(8000)

      egress = app2_network_policies.first['spec']['egress']
      expect(app2_network_policies.size).to eq(2)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e2')
      expect(app2_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e2_-app2'
      )
      expect(app2_network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to eq(1)
      expect(egress.first['to'].size).to eq(1)
      expect(egress.first['ports'].size).to eq(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1_-app1'
      )
      expect(egress.first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to eq(8000)
    end

    it 'should fail when dependency does not provide endpoints' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app'
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
  end

  describe 'stacks' do
    it 'should allow app services to be k8s or non-k8s by environment' do
      factory = eval_stacks do
        stack "mystack" do
          app_service 'app1', :kubernetes => { 'e1' => true, 'e2' => false } do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'myapp'
          end
        end
        env "e1", :primary_site => "space" do
          instantiate_stack "mystack"
        end
        env "e2", :primary_site => "space" do
          instantiate_stack "mystack"
        end
      end

      e1_mystack = factory.inventory.find_environment('e1').definitions['mystack']
      expect(e1_mystack.definitions.size).to eq(0)
      expect(e1_mystack.k8s_machinesets.size).to eq(1)
      e2_mystack = factory.inventory.find_environment('e2').definitions['mystack']
      expect(e2_mystack.definitions.size).to eq(1)
      expect(e2_mystack.k8s_machinesets.size).to eq(0)
    end

    it 'should allow app services to all be k8s' do
      factory = eval_stacks do
        stack "mystack" do
          app_service 'app1', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'myapp'
          end
        end
        env "e1", :primary_site => "space" do
          instantiate_stack "mystack"
        end
        env "e2", :primary_site => "space" do
          instantiate_stack "mystack"
        end
      end

      e1_mystack = factory.inventory.find_environment('e1').definitions['mystack']
      expect(e1_mystack.definitions.size).to eq(0)
      expect(e1_mystack.k8s_machinesets.size).to eq(1)
      e2_mystack = factory.inventory.find_environment('e2').definitions['mystack']
      expect(e2_mystack.definitions.size).to eq(0)
      expect(e2_mystack.k8s_machinesets.size).to eq(1)
    end

    it 'should allow app services to not be k8s' do
      factory = eval_stacks do
        stack "mystack" do
          app_service 'app1', :kubernetes => false do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'myapp'
          end
        end
        env "e1", :primary_site => "space" do
          instantiate_stack "mystack"
        end
        env "e2", :primary_site => "space" do
          instantiate_stack "mystack"
        end
      end

      e1_mystack = factory.inventory.find_environment('e1').definitions['mystack']
      expect(e1_mystack.definitions.size).to eq(1)
      expect(e1_mystack.k8s_machinesets.size).to eq(0)
      e2_mystack = factory.inventory.find_environment('e2').definitions['mystack']
      expect(e2_mystack.definitions.size).to eq(1)
      expect(e2_mystack.k8s_machinesets.size).to eq(0)
    end

    it 'should default app services to not be k8s if no kubernetes property is defined' do
      factory = eval_stacks do
        stack "mystack" do
          app_service 'app1' do
            self.application = 'myapp'
          end
          app_service 'app2' do
            self.application = 'myapp'
          end
        end
        env "e1", :primary_site => "space" do
          instantiate_stack "mystack"
        end
        env "e2", :primary_site => "space" do
          instantiate_stack "mystack"
        end
      end

      e1_mystack = factory.inventory.find_environment('e1').definitions['mystack']
      expect(e1_mystack.definitions.size).to eq(2)
      expect(e1_mystack.k8s_machinesets.size).to eq(0)
      e2_mystack = factory.inventory.find_environment('e2').definitions['mystack']
      expect(e2_mystack.definitions.size).to eq(2)
      expect(e2_mystack.k8s_machinesets.size).to eq(0)
    end

    it 'should raise error if any environments where stack is instantiated are not specified' do
      expect do
        eval_stacks do
          stack "mystack" do
            app_service 'app1', :kubernetes => { 'e1' => true } do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'myapp'
            end
          end
          env "e1", :primary_site => "space" do
            instantiate_stack "mystack"
          end
          env "e2", :primary_site => "space" do
            instantiate_stack "mystack"
          end
        end
      end.to raise_error(RuntimeError, match(/all environments/))
    end

    it 'should raise error if kubernetes property for environment is not a boolean' do
      expect do
        eval_stacks do
          stack "mystack" do
            app_service 'app1', :kubernetes => { 'e1' => 'foo' } do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'myapp'
            end
          end
          env "e1", :primary_site => "space" do
            instantiate_stack "mystack"
          end
        end
      end.to raise_error(RuntimeError, match(/not a boolean/))
    end
  end
end
