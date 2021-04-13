require 'stackbuilder/stacks/factory'
require 'test_classes'
require 'spec_helper'

describe 'kubernetes' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:failing_app_deployer) { TestAppDeployer.new(nil) }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e1-x-vip.space.net.local'            => '3.1.4.1',
                          'office-nexus-001.mgmt.lon.net.local' => '3.1.4.11'
                         )
  end
  let(:hiera_provider) do
    TestHieraProvider.new(
      'stacks/application_credentials_selector' => 0,
      'secrety/looking/thing' => 'ENC[GPG,hQIMAyhja+HHo',
      'kubernetes/masters/space' => ['space-kvm-001.space.net.local', 'space-kvm-005.space.net.local', 'space-kvm-010.space.net.local'])
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

  describe "networking" do
    it "should create an ingress policy to allow traffic from aws alb" do
      factory = eval_stacks do
        stack "mystack" do
          app_service "x", :kubernetes => { 'e1' => true } do
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
      resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider)

      expected_network_policy = {
        'apiVersion' => 'networking.k8s.io/v1',
        'kind' => 'NetworkPolicy',
        'metadata' => {
          'name' => 'allow-in-from-aws-alb-9b343fc',
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
            'from' => [
              {
                'ipBlock' => {
                  'cidr' => '10.169.192.0/21'
                }
              }
            ],
            'ports' => [{
              'port' => 'app',
              'protocol' => 'TCP'
            }]
          }],
          'podSelector' => {
            'matchLabels' => {
              'app.kubernetes.io/component' => 'ingress',
              'group' => 'blue',
              'machineset' => 'x'
            }
          },
          'policyTypes' => [
            'Ingress'
          ]
        }
      }

      expect(resources.flat_map(&:resources).find do |r|
        r['kind'] == 'NetworkPolicy' && r['metadata']['name'].start_with?('allow-in-from-aws-alb-')
      end).to eq(expected_network_policy)
    end
  end
end
