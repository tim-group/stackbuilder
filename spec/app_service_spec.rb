require 'stackbuilder/stacks/factory'
require 'test_classes'

describe 'kubernetes' do
  def eval_stacks(&block)
    Stacks::Factory.new(Stacks::Inventory.from(&block))
  end

  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:failing_app_deployer) { TestAppDeployer.new(nil) }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e1-x-vip.space.net.local' => '3.1.4.1',
                          'e1-app1-001.space.net.local' => '3.1.4.1',
                          'e1-app1-002.space.net.local' => '3.1.4.2',
                          'e1-app2-vip.space.net.local' => '3.1.4.3',
                          'e1-app1-vip.space.net.local' => '3.1.4.4',
                          'e2-app2-vip.space.net.local' => '3.1.4.5',
                          'e1-mydb-001.space.net.local' => '3.1.4.6',
                          'e1-mydb-002.space.net.local' => '3.1.4.6')
  end
  let(:hiera_provider) { TestHieraProvider.new('the_hiera_key' => 'the_hiera_value') }

  describe 'app spec' do
    it 'defines a Deployment' do
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
              'app.kubernetes.io/name' => 'myapplication'
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
                'app.kubernetes.io/name' => 'myapplication',
                'app.kubernetes.io/instance' => 'e1-mystack-myapplication',
                'app.kubernetes.io/component' => 'app_service',
                'app.kubernetes.io/version' => '1.2.3',
                'app.kubernetes.io/managed-by' => 'stacks'
              }
            },
            'spec' => {
              'containers' => [{
                'image' => 'repo.net.local:8080/myapplication:1.2.3',
                'name' => 'myapplication',
                'args' => [
                  'java',
                  '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5000',
                  '-jar',
                  '/app/app.jar',
                  'config.properties'
                ],
                'ports' => [{
                  'containerPort' => 8000,
                  'name' => 'myapplication'
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
                  'name' => 'myapplication-config'
                }
              }]
            }
          }
        }
      }
      expect(k8s.find { |s| s['kind'] == 'Deployment' }).to eql(expected_deployment)

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
            'app.kubernetes.io/name' => 'myapplication',
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
      expect(k8s.find { |s| s['kind'] == 'Service' }).to eql(expected_service)

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

log.directory=/var/log/MyApplication/e1-MyApplication-blue
log.tags=["env:e1", "app:MyApplication", "instance:blue"]

graphite.enabled=true
graphite.host=space-mon-001.mgmt.space.net.local
graphite.port=2013
graphite.prefix=myapplication.k8s_e1_space
graphite.period=10
EOL
        }
      }
      expect(k8s.find { |s| s['kind'] == 'ConfigMap' }).to eql(expected_config_map)

      ordering = {}
      k8s.each_with_index { |s, index| ordering[s['kind']] = index }
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
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).find { |s| s['kind'] == 'Deployment' }['spec']['replicas']).to eql(3000)
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
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
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
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).
                 find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
        to match(/site=space/)
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
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).
                 find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
        to match(/db.exampledb.hostname=e1-mydb-001.space.net.local.*
                  db.exampledb.database=exampledb.*
                  db.exampledb.driver=com.mysql.jdbc.Driver.*
                  db.exampledb.port=3306.*
                  db.exampledb.username=MyApplication.*
                  db.exampledb.password_hiera_key=e1\/MyApplication\/mysql_password.*
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
  end

  describe 'dependencies' do
    def network_policies_for(factory, env, stack, service)
      machine_sets = factory.inventory.find_environment(env).definitions[stack].k8s_machinesets
      machine_set = machine_sets[service]

      machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).select do |policy|
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

      network_policies = app2_machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).select do |policy|
        policy['kind'] == "NetworkPolicy"
      end

      expect(network_policies.size).to eq(1)
      expect(network_policies.first['metadata']['name']).to eql('allow-e1-app1-in-to-app2-8000')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['labels']).to eql({
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      })
      expect(network_policies.first['spec']['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
      })
      expect(network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(network_policies.first['spec']['ingress'].size).to eq(1)
      expect(network_policies.first['spec']['ingress'].first['from'].size).to eq(2)
      expect(network_policies.first['spec']['ingress'].first['ports'].size).to eq(1)
      expect(network_policies.first['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.1/32' })
      expect(network_policies.first['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.2/32' })
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

      network_policies = app2_machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).select do |policy|
        policy['kind'] == "NetworkPolicy"
      end

      expect(network_policies.size).to eq(1)
      expect(network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['labels']).to eql({
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      })
      expect(network_policies.first['spec']['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
      })
      expect(network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(network_policies.first['spec']['egress'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['to'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['ports'].size).to eq(1)
      expect(network_policies.first['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.4/32' })
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
      expect(app1_network_policies.first['metadata']['labels']).to eql({
        'stack' => 'test_app_servers',
        'machineset' => 'app1',
        'app.kubernetes.io/name' => 'app1',
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app1',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      })
      expect(app1_network_policies.first['spec']['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app1',
      })
      expect(app1_network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to eq(1)
      expect(ingress.first['from'].size).to eq(1)
      expect(ingress.first['ports'].size).to eq(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
      })
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(ingress.first['ports'].first['protocol']).to eql('TCP')
      expect(ingress.first['ports'].first['port']).to eq(8000)

      egress = app2_network_policies.first['spec']['egress']
      expect(app2_network_policies.size).to eq(1)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app2_network_policies.first['metadata']['labels']).to eql({
        'stack' => 'test_app_servers',
        'machineset' => 'app2',
        'app.kubernetes.io/name' => 'app2',
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
        'app.kubernetes.io/component' => 'app_service',
        'app.kubernetes.io/version' => '1.2.3',
        'app.kubernetes.io/managed-by' => 'stacks'
      })
      expect(app2_network_policies.first['spec']['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app2',
      })
      expect(app2_network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to eq(1)
      expect(egress.first['to'].size).to eq(1)
      expect(egress.first['ports'].size).to eq(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e1-test_app_servers-app1',
      })
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
      expect(app1_network_policies.first['spec']['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e1-test_app_server1-app1',
      })
      expect(app1_network_policies.first['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to eq(1)
      expect(ingress.first['from'].size).to eq(1)
      expect(ingress.first['ports'].size).to eq(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e2-test_app_server2-app2',
      })
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e2')
      expect(ingress.first['ports'].first['protocol']).to eql('TCP')
      expect(ingress.first['ports'].first['port']).to eq(8000)

      egress = app2_network_policies.first['spec']['egress']
      expect(app2_network_policies.size).to eq(1)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e2')
      expect(app2_network_policies.first['spec']['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e2-test_app_server2-app2',
      })
      expect(app2_network_policies.first['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to eq(1)
      expect(egress.first['to'].size).to eq(1)
      expect(egress.first['ports'].size).to eq(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']).to eql({
        'app.kubernetes.io/instance' => 'e1-test_app_server1-app1',
      })
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
