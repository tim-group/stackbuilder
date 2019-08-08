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
                          'e1-mydb-002.space.net.local' => '3.1.4.8')
  end
  let(:hiera_provider) do
    TestHieraProvider.new(
      'stacks/application_credentials_selector' => 0)
  end

  describe 'resource definitions' do
    it 'defines a Deployment' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.application = 'MyApplication'
            self.jvm_args = '-XX:+UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled'
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      machine_sets = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets
      k8s = machine_sets['x'].to_k8s(app_deployer, dns_resolver, hiera_provider)
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
            'app.kubernetes.io/instance' => 'e1-mystack-myapplication',
            'app.kubernetes.io/component' => 'app_service',
            'app.kubernetes.io/version' => '1.2.3',
            'app.kubernetes.io/managed-by' => 'stacks'
          }
        },
        'spec' => {
          'selector' => {
            'matchLabels' => {
              'app.kubernetes.io/instance' => 'e1-mystack-myapplication',
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
                'app.kubernetes.io/instance' => 'e1-mystack-myapplication',
                'app.kubernetes.io/component' => 'app_service',
                'app.kubernetes.io/version' => '1.2.3',
                'app.kubernetes.io/managed-by' => 'stacks',
                'stack' => 'mystack'
              }
            },
            'spec' => {
              'initContainers' => [{
                'image' => 'repo.net.local:8080/config-generator:1.0.1',
                'name' => 'config-generator',
                'env' => [],
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
                'image' => 'repo.net.local:8080/myapplication:1.2.3',
                'name' => 'myapplication',
                'args' => [
                  'java',
                  '-Djava.awt.headless=true',
                  '-Dfile.encoding=UTF-8',
                  '-XX:ErrorFile=/var/log/app/error.log',
                  '-XX:HeapDumpPath=/var/log/app',
                  '-XX:+HeapDumpOnOutOfMemoryError',
                  '-Djava.security.egd=file:/dev/./urandom',
                  '-Xlog:gc*,safepoint:/var/log/app/gc.log:time,uptime,level,tags:filecount=10,filesize=26214400',
                  '-XX:+UseConcMarkSweepGC',
                  '-XX:+CMSClassUnloadingEnabled',
                  '-Xmx64M',
                  '-jar',
                  '/app/app.jar',
                  '/config/config.properties'
                ],
                'resources' => {
                  'limits' => { 'memory' => '72089Ki' },
                  'requests' => { 'memory' => '72089Ki' }
                },
                'ports' => [
                  {
                    'containerPort' => 8000,
                    'name' => 'app'
                  },
                  {
                    'containerPort' => 5000,
                    'name' => 'debug'
                  }
                ],
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
                  'configMap' => {
                    'name' => 'myapplication-config'
                  }
                }]
            }
          }
        }
      }
      expect(k8s.resources.find { |s| s['kind'] == 'Deployment' }).to eql(expected_deployment)

      expected_service = {
        'apiVersion' => 'v1',
        'kind' => 'Service',
        'metadata' => {
          'name' => 'myapplication',
          'namespace' => 'e1',
          'labels' => {
            'stack' => 'mystack',
            'machineset' => 'x',
            'app.kubernetes.io/name' => 'myapplication',
            'app.kubernetes.io/instance' => 'e1-mystack-myapplication',
            'app.kubernetes.io/component' => 'app_service',
            'app.kubernetes.io/version' => '1.2.3',
            'app.kubernetes.io/managed-by' => 'stacks'
          }
        },
        'spec' => {
          'type' => 'LoadBalancer',
          'selector' => {
            'app.kubernetes.io/instance' => 'e1-mystack-myapplication',
            'participation' => 'enabled'
          },
          'ports' => [{
            'name' => 'app',
            'protocol' => 'TCP',
            'port' => 8000,
            'targetPort' => 8000
          }],
          'loadBalancerIP' => '3.1.4.1'
        }
      }
      expect(k8s.resources.find { |s| s['kind'] == 'Service' }).to eql(expected_service)

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
            'app.kubernetes.io/instance' => 'e1-mystack-myapplication',
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

graphite.enabled=true
graphite.host=space-mon-001.mgmt.space.net.local
graphite.port=2013
graphite.prefix=myapplication.k8s_e1_space
graphite.period=10
EOL
        }
      }
      expect(k8s.resources.find { |s| s['kind'] == 'ConfigMap' }).to eql(expected_config_map)

      ordering = {}
      k8s.resources.each_with_index { |s, index| ordering[s['kind']] = index }
      expect(ordering['Service']).to be < ordering['Deployment']
      expect(ordering['ConfigMap']).to be < ordering['Deployment']
    end

    it 'controls the number of replicas' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.application = 'MyApplication'
            self.instances = 3000
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.find { |s| s['kind'] == 'Deployment' }['spec']['replicas']).to eql(3000)
    end

    it 'labels metrics using the site' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.application = 'MyApplication'
            self.instances = 1
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
        to match(/space-mon-001.mgmt.space.net.local/)
    end

    it 'generates config from app-defined template' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
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
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.
                 find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
        to match(/site=space/)
    end

    it 'tracks secrets needed from hiera' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
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
      k8s = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

      expect(k8s.resources.find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
        to match(/secret={SECRET:my_very_secret_data.*array_secret={SECRET:my_very_secret_array_0/m)

      expect(k8s.resources.find { |s| s['kind'] == 'Deployment' }['spec']['template']['spec']['initContainers'].
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

      expect(k8s.resources.find { |s| s['kind'] == 'Deployment' }['spec']['template']['spec']['initContainers'].
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

      expect(k8s.secrets).to eql(
        'my/very/secret.data' => 'my_very_secret_data',
        'my/very/secret.array' => 'my_very_secret_array_0')
    end

    it 'has config for it\'s db dependencies' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
            self.application = 'MyApplication'
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
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
          instantiate_stack "my_db"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.
                 find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
        to match(/db.exampledb.hostname=e1-mydb-001.space.net.local.*
                  db.exampledb.database=exampledb.*
                  db.exampledb.driver=com.mysql.jdbc.Driver.*
                  db.exampledb.port=3306.*
                  db.exampledb.username=MyApplication0.*
                  db.exampledb.password=\{SECRET:e1_MyApplication_mysql_passwords_0\}.*
                  db.exampledb.read_only_cluster=e1-mydb-002.space.net.local.*
                 /mx)
    end

    it 'fails when the app version cannot be found' do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => true do
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

    describe 'memory limits (max) and requests (min) ' do
      def k8s_resource(set, kind)
        set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.find { |s| s['kind'] == kind }
      end

      it 'bases container limits and requests on the max heap memory' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
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

        expect(app_container['resources']['limits']['memory']).to eq('115343360Ki')
        expect(app_container['resources']['requests']['memory']).to eq('115343360Ki')
        expect(app_container['args'].find { |arg| arg =~ /-Xmx/ }).to match(/-Xmx100G/)
      end

      it 'controls container limits by reserving headspace computed from the heap size' do
        factory = eval_stacks do
          stack "mystack" do
            app_service "x", :kubernetes => true do
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

        expect(app_container['resources']['limits']['memory']).to eq('157286400Ki')
        expect(app_container['resources']['requests']['memory']).to eq('157286400Ki')
        expect(app_container['args'].find { |arg| arg =~ /-Xmx/ }).to match(/-Xmx100G/)
      end
    end
  end

  describe 'dependencies' do
    def network_policies_for(factory, env, stack, service)
      machine_sets = factory.inventory.find_environment(env).definitions[stack].k8s_machinesets
      machine_set = machine_sets[service]

      machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.select do |policy|
        policy['kind'] == "NetworkPolicy"
      end
    end

    it 'should create the correct ingress network policies for a service in kubernetes when another non kubernetes service depends on it' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1' do
            depend_on 'app2'
          end

          app_service 'app2', :kubernetes => true do
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

      network_policies = app2_machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.select do |policy|
        policy['kind'] == "NetworkPolicy"
      end

      expect(network_policies.size).to eq(1)
      expect(network_policies.first['metadata']['name']).to eql('allow-e1-app1-in-to-app2-8000')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2'
      )
      expect(network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(network_policies.first['spec']['ingress'].size).to eq(1)
      expect(network_policies.first['spec']['ingress'].first['from'].size).to eq(2)
      expect(network_policies.first['spec']['ingress'].first['ports'].size).to eq(1)
      expect(network_policies.first['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.2/32' })
      expect(network_policies.first['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.3/32' })
      expect(network_policies.first['spec']['ingress'].first['ports'].first['protocol']).to eql('TCP')
      expect(network_policies.first['spec']['ingress'].first['ports'].first['port']).to eq(8000)
    end

    it 'should create the correct egress network policies for a service in kubernetes when that service depends on another non kubernetes service' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1' do
            self.application = 'app1'
          end

          app_service 'app2', :kubernetes => true do
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

      network_policies = app2_machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.select do |policy|
        policy['kind'] == "NetworkPolicy"
      end

      expect(network_policies.size).to eq(1)
      expect(network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2'
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
            self.application = 'app1'
          end

          app_service 'app2', :kubernetes => true do
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
      expect(app1_network_policies.size).to eq(1)
      expect(app1_network_policies.first['metadata']['name']).to eql('allow-e1-app2-in-to-app1-8000')
      expect(app1_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app1_network_policies.first['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app1',
        'app.kubernetes.io/name' => 'app1',
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app1',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(app1_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app1'
      )
      expect(app1_network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to eq(1)
      expect(ingress.first['from'].size).to eq(1)
      expect(ingress.first['ports'].size).to eq(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2'
      )
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(ingress.first['ports'].first['protocol']).to eql('TCP')
      expect(ingress.first['ports'].first['port']).to eq(8000)

      egress = app2_network_policies.first['spec']['egress']
      expect(app2_network_policies.size).to eq(1)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app2_network_policies.first['metadata']['labels']).to eql(
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      )
      expect(app2_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2'
      )
      expect(app2_network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to eq(1)
      expect(egress.first['to'].size).to eq(1)
      expect(egress.first['ports'].size).to eq(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app1'
      )
      expect(egress.first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to eq(8000)
    end

    it 'should create the correct network policies for two services in \
kubernetes in different environments in the same site when one service \
depends on the other' do
      factory = eval_stacks do
        stack "test_app_server1" do
          app_service 'app1', :kubernetes => true do
            self.application = 'app1'
          end
        end
        stack "test_app_server2" do
          app_service 'app2', :kubernetes => true do
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
      expect(app1_network_policies.size).to eq(1)
      expect(app1_network_policies.first['metadata']['name']).to eql('allow-e2-app2-in-to-app1-8000')
      expect(app1_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app1_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1-test_app_server1-app1'
      )
      expect(app1_network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to eq(1)
      expect(ingress.first['from'].size).to eq(1)
      expect(ingress.first['ports'].size).to eq(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e2-test_app_server2-app2'
      )
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e2')
      expect(ingress.first['ports'].first['protocol']).to eql('TCP')
      expect(ingress.first['ports'].first['port']).to eq(8000)

      egress = app2_network_policies.first['spec']['egress']
      expect(app2_network_policies.size).to eq(1)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e2')
      expect(app2_network_policies.first['spec']['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e2-test_app_server2-app2'
      )
      expect(app2_network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to eq(1)
      expect(egress.first['to'].size).to eq(1)
      expect(egress.first['ports'].size).to eq(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']).to eql(
        'app.kubernetes.io/instance' => 'e1-test_app_server1-app1'
      )
      expect(egress.first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to eq(8000)
    end

    it 'should fail when dependency does not provide endpoints' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1', :kubernetes => true do
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
