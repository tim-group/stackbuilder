require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'
require 'resolv'

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
        app_service "x", :kubernetes => true do
          self.application = 'MyApplication'
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    machineset("x") do |set|
      k8s = set.to_k8s(app_deployer, dns_resolver)
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
        app_service "x", :kubernetes => true do
          self.application = 'MyApplication'
          self.instances = 3000
        end
      end
      env "e1", :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
    machineset("x") do |set|
      expect(set.to_k8s(app_deployer, dns_resolver).find { |s| s['kind'] == 'Deployment' }['spec']['replicas']).to eql(3000)
    end
  end

  describe_stack 'labels metrics using the site' do
    given do
      stack "mystack" do
        app_service "x", :kubernetes => true do
          self.application = 'MyApplication'
          self.instances = { 'earth' => 1 }
        end
      end
      env "e1", :primary_site => 'space', :secondary_site => 'earth' do
        instantiate_stack "mystack"
      end
    end
    machineset("x") do |set|
      expect(set.to_k8s(app_deployer, dns_resolver).find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
        to match(/earth-mon-001.mgmt.earth.net.local/)
    end
  end

  describe_stack 'generates config from app-defined template' do
    given do
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
    machineset("x") do |set|
      expect(set.to_k8s(app_deployer, dns_resolver).find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).to match(/site=space/)
    end
  end
end
