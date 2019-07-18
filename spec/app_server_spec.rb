require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'
require 'resolv'

describe_stack 'test_app_server' do
  given do
    stack "test_app_server" do
      app_service "appx" do
        self.application = "JavaHttpRef"
        each_machine do |machine|
          machine.launch_config['specify_config_as_system_property'] = 'yes'
        end
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app']['launch_config']).to eql('specify_config_as_system_property' => 'yes')
  end
end

describe_stack 'test_app_server should default to no jvm args' do
  given do
    stack "test_app_server" do
      app_service "appx" do
        self.application = "JavaHttpRef"
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app'].key?('jvm_args')).to eql(false)
  end
end

describe_stack 'test_app_server with custom jvm args' do
  given do
    stack "test_app_server" do
      app_service "appx" do
        self.application = "JavaHttpRef"
        @jvm_args = '-Xms256m -Xmx256m -XX:CMSInitiatingOccupancyFraction=55 -XX:+UseCompressedOops ' \
          '-XX:+UseConcMarkSweepGC -XX:MaxPermSize=128M -XX:+CMSClassUnloadingEnabled'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app']['jvm_args']).to eql('-Xms256m -Xmx256m ' \
      '-XX:CMSInitiatingOccupancyFraction=55 -XX:+UseCompressedOops -XX:+UseConcMarkSweepGC ' \
      '-XX:MaxPermSize=128M -XX:+CMSClassUnloadingEnabled')
  end
end

describe_stack 'test_app_server with only one instance in the load balancer' do
  given do
    stack "test_app_server" do
      loadbalancer_service
      app_service "appx" do
        self.application = "JavaHttpRef"
        @one_instance_in_lb = true
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-lb-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::loadbalancer']['virtual_servers']['e1-appx-vip.space.net.local']
    expect(enc['type']).to eql 'one_instance_in_lb_with_sorry_server'
  end
end

describe_stack 'should have the correct app_dependant_instances and participation_dependant_instances' do
  given do
    stack 'loadbalancer' do
      loadbalancer_service
    end

    stack 'example' do
      app_service "appx" do
        self.application = "JavaHttpRef"
      end
      app_service "appy" do
        self.application = "JavaHttpRef"
        depend_on "appx"
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "loadbalancer"
      instantiate_stack "example"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-appx-001.mgmt.space.net.local',
        'e1-appx-002.mgmt.space.net.local',
        'e1-appy-001.mgmt.space.net.local',
        'e1-appy-002.mgmt.space.net.local',
        'e1-lb-001.mgmt.space.net.local',
        'e1-lb-002.mgmt.space.net.local'
      ]
    )
  end

  host("e1-appy-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::http_app']
    expect(enc['participation_dependant_instances']).to include('e1-lb-001.space.net.local',
                                                                'e1-lb-002.space.net.local')
    expect(enc['participation_dependant_instances'].size).to eql(2)
    expect(enc['application_dependant_instances']).to include('e1-lb-001.space.net.local', 'e1-lb-002.space.net.local')
    expect(enc['application_dependant_instances'].size).to eql(2)
  end

  host("e1-appx-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::http_app']
    expect(enc['participation_dependant_instances']).to include('e1-lb-001.space.net.local',
                                                                'e1-lb-002.space.net.local')
    expect(enc['participation_dependant_instances'].size).to eql(2)
    expect(enc['application_dependant_instances']).to include('e1-lb-001.space.net.local',
                                                              'e1-lb-002.space.net.local',
                                                              'e1-appy-001.space.net.local',
                                                              'e1-appy-002.space.net.local')
    expect(enc['application_dependant_instances'].size).to eql(4)
  end
end

describe_stack 'test_app_server_with_rabbit_logging_dependencies' do
  given do
    stack "test_app_server" do
      app_service 'myapp' do
        self.groups = ['blue']
        self.application = 'rw-app'
        depend_on 'rabbitmq-elasticsearch', environment.name
      end
    end

    stack 'centralised_logging_cluster' do
      rabbitmq_logging 'rabbitmq-elasticsearch'
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
      instantiate_stack "centralised_logging_cluster"
    end
  end

  host("e1-rabbitmq-elasticsearch-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::rabbitmq_logging']
    expect(enc['dependant_instances']).to include(
      'e1-myapp-001.space.net.local',
      'e1-myapp-002.space.net.local',
      'e1-rabbitmq-elasticsearch-002.space.net.local')
    expect(enc['dependant_users']).to have_key('rw-app')
  end

  host("e1-myapp-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::http_app']['dependencies']
    expect(enc['logging.rabbit.clusternodes']).to include(
      'e1-rabbitmq-elasticsearch-001.space.net.local,e1-rabbitmq-elasticsearch-002.space.net.local')
    expect(enc['logging.rabbit.username']).to include('rw-app')
    expect(enc['logging.rabbit.password_hiera_key']).to include('e1/rw-app/messaging_password')
  end
end

describe_stack 'test_app_server that uses docker' do
  given do
    stack "test_app_server" do
      app_service 'myapp' do
        self.groups = ['blue']
        self.application = 'rw-app'
        self.use_docker = true
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test_app_server"
    end
  end

  host("e1-myapp-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app']['use_docker']).to eql(true)
  end
end

describe 'kubernetes' do
  def eval_stacks(&block)
    Stacks::Factory.new(Stacks::Inventory.from(&block))
  end

  class TestAppDeployer
    def initialize(version)
      @version = version
    end

    def query_cmdb_for(_spec)
      { :target_version => @version }
    end
  end

  class MyTestDnsResolver
    def initialize(ip_address_map)
      @ip_address_map = ip_address_map
    end

    def lookup(fqdn)
      Resolv::IPv4.create(@ip_address_map[fqdn])
    rescue ArgumentError
      raise Resolv::ResolvError "no address for #{fqdn}"
    end
  end

  class TestHieraProvider
    def initialize(data)
      @data = data
    end

    def lookup(_machineset, key, default_value = nil)
      @data.key?(key) ? @data[key] : default_value
    end
  end

  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e1-x-vip.space.net.local' => '3.1.4.1',
                          'e1-app1-001.space.net.local' => '3.1.4.1',
                          'e1-app1-002.space.net.local' => '3.1.4.2',
                          'e1-app2-vip.space.net.local' => '3.1.4.3',
                          'e1-app1-vip.space.net.local' => '3.1.4.4',
                          'e2-app2-vip.space.net.local' => '3.1.4.5')
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
            'machineset' => 'x'
          }
        },
        'spec' => {
          'selector' => {
            'matchLabels' => {
              'app' => 'myapplication'
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
                'app' => 'myapplication'
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
                    'path' => '/info/health',
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
            'machineset' => 'x'
          }
        },
        'spec' => {
          'type' => 'LoadBalancer',
          'selector' => {
            'app' => 'myapplication'
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
            'machineset' => 'x'
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
  site=<%= @environment.sites.first %>
EOL
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expect(set.to_k8s(app_deployer, dns_resolver, hiera_provider).find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).to match(/site=space/)
    end
  end

  describe 'dependencies' do
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

      expect(network_policies.size).to be(1)
      expect(network_policies.first['metadata']['name']).to eql('allow-e1-app1-in-to-app2-8000')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['spec']['podSelector']['matchLabels']['machine_set']).to eql('app2')
      expect(network_policies.first['metadata']['spec']['podSelector']['matchLabels']['stack']).to eql('test_app_servers')
      expect(network_policies.first['metadata']['spec']['policyTypes']).to eql(['Ingress'])
      expect(network_policies.first['metadata']['spec']['ingress'].size).to be(1)
      expect(network_policies.first['metadata']['spec']['ingress'].first['from'].size).to be(2)
      expect(network_policies.first['metadata']['spec']['ingress'].first['ports'].size).to be(1)
      expect(network_policies.first['metadata']['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.1/32' })
      expect(network_policies.first['metadata']['spec']['ingress'].first['from']).to include('ipBlock' => { 'cidr' => '3.1.4.2/32' })
      expect(network_policies.first['metadata']['spec']['ingress'].first['ports'].first['protocol']).to eql('TCP')
      expect(network_policies.first['metadata']['spec']['ingress'].first['ports'].first['port']).to be(8000)
    end

    it 'should create the correct egress network policies for a service in kubernetes when that service depends on another non kubernetes service' do
      factory = eval_stacks do
        stack "test_app_servers" do
          app_service 'app1' do
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

      expect(network_policies.size).to be(1)
      expect(network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['metadata']['spec']['podSelector']['matchLabels']['machine_set']).to eql('app2')
      expect(network_policies.first['metadata']['spec']['podSelector']['matchLabels']['stack']).to eql('test_app_servers')
      expect(network_policies.first['metadata']['spec']['policyTypes']).to eql(['Egress'])
      expect(network_policies.first['metadata']['spec']['egress'].size).to be(1)
      expect(network_policies.first['metadata']['spec']['egress'].first['to'].size).to be(1)
      expect(network_policies.first['metadata']['spec']['egress'].first['ports'].size).to be(1)
      expect(network_policies.first['metadata']['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.4/32' })
      expect(network_policies.first['metadata']['spec']['egress'].first['ports'].first['protocol']).to eql('TCP')
      expect(network_policies.first['metadata']['spec']['egress'].first['ports'].first['port']).to be(8000)
    end

    it 'should create the correct network policies for two services in kubernetes in the same environment when one service depends on the other' do
      def network_policies_for(factory, env, stack, service)
        machine_sets = factory.inventory.find_environment(env).definitions[stack].k8s_machinesets
        machine_set = machine_sets[service]

        machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).select do |policy|
          policy['kind'] == "NetworkPolicy"
        end
      end

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

      ingress = app1_network_policies.first['metadata']['spec']['ingress']
      expect(app1_network_policies.size).to be(1)
      expect(app1_network_policies.first['metadata']['name']).to eql('allow-e1-app2-in-to-app1-8000')
      expect(app1_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app1_network_policies.first['metadata']['spec']['podSelector']['matchLabels']['machine_set']).to eql('app1')
      expect(app1_network_policies.first['metadata']['spec']['podSelector']['matchLabels']['stack']).to eql('test_app_servers')
      expect(app1_network_policies.first['metadata']['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to be(1)
      expect(ingress.first['from'].size).to be(1)
      expect(ingress.first['ports'].size).to be(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']['machine_set']).to eql('app2')
      expect(ingress.first['from'].first['podSelector']['matchLabels']['stack']).to eql('test_app_servers')
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(ingress.first['ports'].first['protocol']).to eql('TCP')
      expect(ingress.first['ports'].first['port']).to be(8000)

      egress = app2_network_policies.first['metadata']['spec']['egress']
      expect(app2_network_policies.size).to be(1)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app2_network_policies.first['metadata']['spec']['podSelector']['matchLabels']['machine_set']).to eql('app2')
      expect(app2_network_policies.first['metadata']['spec']['podSelector']['matchLabels']['stack']).to eql('test_app_servers')
      expect(app2_network_policies.first['metadata']['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to be(1)
      expect(egress.first['to'].size).to be(1)
      expect(egress.first['ports'].size).to be(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']['machine_set']).to eql('app1')
      expect(egress.first['to'].first['podSelector']['matchLabels']['stack']).to eql('test_app_servers')
      expect(egress.first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to be(8000)
    end

    it 'should create the correct network policies for two services in \
kubernetes in different environments in the same site when one service \
depends on the other' do
      def network_policies_for(factory, env, stack, service)
        machine_sets = factory.inventory.find_environment(env).definitions[stack].k8s_machinesets
        machine_set = machine_sets[service]

        machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).select do |policy|
          policy['kind'] == "NetworkPolicy"
        end
      end

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

      ingress = app1_network_policies.first['metadata']['spec']['ingress']
      expect(app1_network_policies.size).to be(1)
      expect(app1_network_policies.first['metadata']['name']).to eql('allow-e2-app2-in-to-app1-8000')
      expect(app1_network_policies.first['metadata']['namespace']).to eql('e1')
      expect(app1_network_policies.first['metadata']['spec']['podSelector']['matchLabels']['machine_set']).to eql('app1')
      expect(app1_network_policies.first['metadata']['spec']['podSelector']['matchLabels']['stack']).to eql('test_app_server1')
      expect(app1_network_policies.first['metadata']['spec']['policyTypes']).to eql(['Ingress'])
      expect(ingress.size).to be(1)
      expect(ingress.first['from'].size).to be(1)
      expect(ingress.first['ports'].size).to be(1)
      expect(ingress.first['from'].first['podSelector']['matchLabels']['machine_set']).to eql('app2')
      expect(ingress.first['from'].first['podSelector']['matchLabels']['stack']).to eql('test_app_server2')
      expect(ingress.first['from'].first['namespaceSelector']['matchLabels']['name']).to eql('e2')
      expect(ingress.first['ports'].first['protocol']).to eql('TCP')
      expect(ingress.first['ports'].first['port']).to be(8000)

      egress = app2_network_policies.first['metadata']['spec']['egress']
      expect(app2_network_policies.size).to be(1)
      expect(app2_network_policies.first['metadata']['name']).to eql('allow-app2-out-to-e1-app1-8000')
      expect(app2_network_policies.first['metadata']['namespace']).to eql('e2')
      expect(app2_network_policies.first['metadata']['spec']['podSelector']['matchLabels']['machine_set']).to eql('app2')
      expect(app2_network_policies.first['metadata']['spec']['podSelector']['matchLabels']['stack']).to eql('test_app_server2')
      expect(app2_network_policies.first['metadata']['spec']['policyTypes']).to eql(['Egress'])
      expect(egress.size).to be(1)
      expect(egress.first['to'].size).to be(1)
      expect(egress.first['ports'].size).to be(1)
      expect(egress.first['to'].first['podSelector']['matchLabels']['machine_set']).to eql('app1')
      expect(egress.first['to'].first['podSelector']['matchLabels']['stack']).to eql('test_app_server1')
      expect(egress.first['to'].first['namespaceSelector']['matchLabels']['name']).to eql('e1')
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to be(8000)
    end
  end
end
