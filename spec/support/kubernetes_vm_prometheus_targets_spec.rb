require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/kubernetes_vm_prometheus_targets'
require 'test_classes'
require 'spec_helper'

describe Support::KubernetesVmPrometheusTargets do
  let(:factory) do
    eval_stacks do
      stack "appstack" do
        app_service "appstack" do
          self.application = 'MyApplication'
          self.instances = 2
          self.scrape_metrics = true
        end
      end
      stack "k8sstack" do
        app_service "k8sappservice", :kubernetes => true do
          self.maintainers = [person('Testers')]
          self.description = 'Testing'

          self.application = 'MyK8sApplication'
          self.instances = 2
        end
      end
      stack "mysql_stack" do
        mysql_cluster "db" do
          self.database_name = 'my_application'
        end
      end
      stack "no_scrape_app_stack" do
        app_service "noscrape" do
          self.application = 'MyApplication'
          self.instances = 1
          self.scrape_metrics = false
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "appstack"
        instantiate_stack "k8sstack"
      end
    end
  end

  let(:dns_resolver) do
    MyTestDnsResolver.new(
      'e1-appstack-001.space.net.local' => '3.4.5.6',
      'e1-appstack-002.space.net.local' => '3.4.5.7'
    )
  end

  describe 'stacks:kubernetes_vm_prometheus_targets' do
    it "generates_crd_with_all_attributes" do
      vm_prom_targets = Support::KubernetesVmPrometheusTargets.new(dns_resolver)
      out = vm_prom_targets.generate(factory.inventory.environments.map(&:last), 'space')

      expect(out.select { |crd| crd['metadata']['name'] == 'metrics-e1-appstack-001' }).to eq([
        {
          'apiVersion' => 'v1',
          'kind' => 'Service',
          'metadata' => {
            'name' => "metrics-e1-appstack-001",
            'namespace' => 'vm-metrics',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'app.kubernetes.io/component' => 'vm_metrics_target',
              'app' => 'MyApplication',
              'group' => 'blue',
              'server' => 'e1-appstack-001_mgmt_space_net_local',
              'environment' => 'e1'
            }
          },
          'spec' => {
            'type' => 'ExternalName',
            'externalName' => 'vm-metrics-e1-appstack-001.space.net.local',
            'ports' => [{
              'name' => 'metrics',
              'port' => 8000,
              'targetPort' => 8000
            }]
          }
        },
        {
          'apiVersion' => 'v1',
          'kind' => 'Endpoints',
          'metadata' => {
            'name' => "metrics-e1-appstack-001",
            'namespace' => 'vm-metrics',
            'labels' => {
              'app.kubernetes.io/managed-by' => 'stacks',
              'app.kubernetes.io/component' => 'vm_metrics_target'
            }
          },
          'subsets' => [{
            'addresses' => [{ 'ip' => '3.4.5.6' }],
            'ports' => [{
              'name' => 'metrics',
              'port' => 8000,
              'protocol' => 'TCP'
            }]
          }]
        }
      ]
                                                                                             )
    end

    it "ignores_stacks_without_scrape_metrics" do
      vm_prom_targets = Support::KubernetesVmPrometheusTargets.new(dns_resolver)
      out = vm_prom_targets.generate(factory.inventory.environments.map(&:last), 'space')

      expect(out.map { |crd| [crd['kind'], crd['metadata']['name']] }).to match_array([
        ['Service', 'metrics-e1-appstack-001'],
        ['Endpoints', 'metrics-e1-appstack-001'],
        ['Service', 'metrics-e1-appstack-002'],
        ['Endpoints', 'metrics-e1-appstack-002']
      ])
    end
  end
end
