require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'
require 'resolv'

describe 'Stacks::MachineSet' do
  describe_stack 'allows creation of secondary servers' do
    given do
      stack "funds" do
        app_service 'fundsapp' do
          self.instances = 1
          @enable_secondary_site = true
        end
        app_service 'dumbapp' do
          self.instances = 1
          @enable_secondary_site = false
        end
      end

      env 'env', :primary_site => 'mars', :secondary_site => 'jupiter' do
        instantiate_stack 'funds'
      end
    end
    it_stack 'should contain 1 server in each site' do |stack|
      expect(stack).to have_host('env-fundsapp-001.mgmt.mars.net.local')
      expect(stack).to have_host('env-fundsapp-001.mgmt.jupiter.net.local')
      expect(stack).to have_host('env-dumbapp-001.mgmt.mars.net.local')
      expect(stack).not_to have_host('env-dumbapp-001.mgmt.jupiter.net.local')
    end
    it_stack 'should put secondary site server in a different cluster' do |stack|
      expect(stack.find("env-fundsapp-001.mgmt.mars.net.local").to_enc['role::http_app']['cluster']).to eql('env-fundsapp-mars')
      expect(stack.find("env-fundsapp-001.mgmt.jupiter.net.local").to_enc['role::http_app']['cluster']).to eql('env-fundsapp-jupiter')
      expect(stack.find("env-dumbapp-001.mgmt.mars.net.local").to_enc['role::http_app']['cluster']).to eql('env-dumbapp')
    end
  end
  describe_stack 'provides an allowed host mechanism that can be used by app_services' do
    given do
      stack "mystack" do
        app_service "x" do
          allow_host '1.1.1.1'
          each_machine do |_machine|
            allow_host '2.2.2.2'
          end
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    it_stack 'allows specification of aditional hosts that are allowed to talk to the app or service' do
      host("e1-x-001.mgmt.space.net.local") do |host|
        expect(host.to_enc['role::http_app']['allowed_hosts']).to eql(['1.1.1.1', '2.2.2.2'])
      end
    end
  end
  describe_stack 'provides an allowed host mechanism that can be used by standalone_app_services' do
    given do
      stack "mystack" do
        standalone_app_service "x" do
          allow_host '1.1.1.1'
          each_machine do |_machine|
            allow_host '2.2.2.2'
          end
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    it_stack 'allows specification of aditional hosts that are allowed to talk to the app or service' do
      host("e1-x-001.mgmt.space.net.local") do |host|
        expect(host.to_enc['role::http_app']['allowed_hosts']).to eql(['1.1.1.1', '2.2.2.2'])
      end
    end
  end
end

describe_stack 'should support instances as a hash' do
  given do
    stack 'example' do
      app_service "appx" do
        self.application = "JavaHttpRef"
        self.instances = { 'earth' => 0, 'jupiter' => 2 }
      end
    end

    env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
      instantiate_stack "example"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-appx-001.mgmt.jupiter.net.local',
        'e1-appx-002.mgmt.jupiter.net.local'
      ]
    )
  end
end

describe_stack 'should support instances as a site hash with roles' do
  given do
    stack 'example' do
      app_service "appx" do
        self.role_in_name = true
        self.application = "JavaHttpRef"
        self.instances = {
          'earth' => {
            :basic => 1
          },
          'jupiter' => {
            :advanced => 1
          }
        }
      end
    end

    env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
      instantiate_stack "example"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-appx-basic-001.mgmt.earth.net.local',
        'e1-appx-advanced-001.mgmt.jupiter.net.local'
      ]
    )
  end
  host("e1-appx-basic-001.mgmt.earth.net.local") do |host|
    expect(host.role).to eql(:basic)
  end
  host("e1-appx-advanced-001.mgmt.jupiter.net.local") do |host|
    expect(host.role).to eql(:advanced)
  end
end

describe_stack 'should support instances as a site hash' do
  given do
    stack 'example' do
      app_service "appx" do
        self.application = "JavaHttpRef"
        self.instances = {
          'earth'   => 1,
          'jupiter' => 1
        }
      end
    end

    env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
      instantiate_stack "example"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-appx-001.mgmt.earth.net.local',
        'e1-appx-001.mgmt.jupiter.net.local'
      ]
    )
  end
  host("e1-appx-001.mgmt.earth.net.local") do |host|
    expect(host.role).to be_nil
  end
  host("e1-appx-001.mgmt.jupiter.net.local") do |host|
    expect(host.role).to be_nil
  end
end

describe_stack 'should explode when using role in name with legacy instances (Integer)' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.role_in_name = true
          self.application = "JavaHttpRef"
          self.instances = 1
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack "example"
      end
    end
  end.to raise_error(/You cannot specify self.role_in_name = true without defining roles in @instances/)
end

describe_stack 'should explode when using role in name with non-role containing instances (Hash)' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.role_in_name = true
          self.application = "JavaHttpRef"
          self.instances = {
            'earth'   => 1,
            'jupiter' => 1
          }
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack "example"
      end
    end
  end.to raise_error(/You cannot specify self.role_in_name = true without defining roles in @instances/)
end

describe_stack 'should raise exception for an un-supported site' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.application = "JavaHttpRef"
          self.instances = { 'earth' => 0, 'jupiter' => 2, 'moon' => 0 }
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack("example")
      end
    end
  end.to raise_error(/e1 environment does not support site\(s\): moon/)
end

describe_stack 'should raise exception if instance count provided is a string with basic @instances(Hash)' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.application = "JavaHttpRef"
          self.instances = { 'earth' => '1' }
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack("example")
      end
    end
  end.to raise_error(/You must specify Integers when using @instances in a hash format/)
end

describe_stack 'should raise exception if instance count provided is a string with role based @instances(Hash)' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.application = "JavaHttpRef"
          self.instances = {
            'earth' => {
              :fish => '1'
            }
          }
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack("example")
      end
    end
  end.to raise_error(/You must specify Integers when using @instances in a hash format/)
end

describe_stack 'should raise exception if @instances is not an Integer or Hash' do
  expect do
    given do
      stack 'example' do
        app_service "appx" do
          self.application = "JavaHttpRef"
          self.instances = 'go fish'
        end
      end

      env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
        instantiate_stack("example")
      end
    end
  end.to raise_error(/You must specify Integer or Hash for @instances. You provided a String/)

  describe_stack 'allows monitoring to be changed at machineset level' do
    given do
      stack "mystack" do
        app_service "x" do
          self.monitoring_in_enc = true
          self.monitoring = false
          self.monitoring_options = {}
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    host("e1-x-001.mgmt.space.net.local") do |host|
      expect(host.to_enc['monitoring']['checks']).to eql(false)
      expect(host.to_enc['monitoring']['options']).to eql({})
    end
  end
end

describe_stack 'Kubernetes' do
  class TestAppDeployer
    def initialize(version)
      @version = version
    end

    def query_cmdb_for(_spec)
      { :target_version => @version }
    end
  end

  app_deployer = TestAppDeployer.new('1.2.3')

  class TestDnsResolver
    def initialize(ip_address)
      @ip_address = ip_address
    end

    def lookup(_fqdn)
      Resolv::IPv4.create(@ip_address)
    end
  end

  dns_resolver = TestDnsResolver.new('3.1.4.1')

  describe_stack 'defines a Deployment' do
    given do
      stack "mystack" do
        app_service "x" do
          self.application = 'MyApplication'
          self.kubernetes = true
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    host("e1-x-001.mgmt.space.net.local") do |host|
      k8s = host.to_k8s(app_deployer, dns_resolver)
      expected_deployment = {
        'apiVersion' => 'apps/v1',
        'kind' => 'Deployment',
        'metadata' => {
          'name' => 'myapplication',
          'namespace' => 'e1'
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
          'namespace' => 'e1'
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
          'namespace' => 'e1'
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
  end

  describe_stack 'controls the number of replicas' do
    given do
      stack "mystack" do
        app_service "x" do
          self.application = 'MyApplication'
          self.instances = 3000
          self.kubernetes = true
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    host("e1-x-001.mgmt.space.net.local") do |host|
      expect(host.to_k8s(app_deployer, dns_resolver).find { |s| s['kind'] == 'Deployment' }['spec']['replicas']).to eql(3000)
    end
  end

  describe_stack 'labels metrics using the site' do
    given do
      stack "mystack" do
        app_service "x" do
          self.application = 'MyApplication'
          self.instances = { 'earth' => 1 }
          self.kubernetes = true
        end
      end
      env "e1", :primary_site => 'space', :secondary_site => 'earth' do
        instantiate_stack "mystack"
      end
    end
    host("e1-x-001.mgmt.earth.net.local") do |host|
      expect(host.to_k8s(app_deployer, dns_resolver).find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
        to match(/earth-mon-001.mgmt.earth.net.local/)
    end
  end

  describe_stack 'generates config from app-defined template' do
    given do
      stack "mystack" do
        app_service "x" do
          self.application = 'MyApplication'
          self.kubernetes = true
          self.appconfig = <<EOL
site=<%= @site %>
EOL
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    host("e1-x-001.mgmt.space.net.local") do |host|
      expect(host.to_k8s(app_deployer, dns_resolver).find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).to match(/site=space/)
    end
  end
end
