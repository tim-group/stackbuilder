require 'stackbuilder/stacks/factory'
require 'test_classes'
require 'spec_helper'

describe 'kubernetes' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:failing_app_deployer) { TestAppDeployer.new(nil) }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e1-x-vip.space.net.local' => '3.1.4.1'
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

  describe 'a cronjob' do
    it 'defines a CronJob' do
      factory = eval_stacks do
        stack "mystack" do
          cronjob_service "x", :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            self.alerts_channel = 'test'
            self.startup_alert_threshold = '1s'

            self.application = 'MyApplication'
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      set = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets['x']
      expected_cronjob = {
        'apiVersion' => 'batch/v1beta1',
        'kind' => 'CronJob',
        'metadata' => {
          'name' => 'x-blue-cronjob',
          'namespace' => 'e1',
          'labels' => {
            'app.kubernetes.io/managed-by' => 'stacks',
            'stack' => 'mystack',
            'machineset' => 'x',
            'group' => 'blue',
            'app.kubernetes.io/instance' => 'blue',
            'app.kubernetes.io/part-of' => 'x',
            'app.kubernetes.io/component' => 'cronjob_service',
            'application' => 'myapplication',
            'app.kubernetes.io/name' => 'myapplication',
            'app.kubernetes.io/version' => '1.2.3'
          },
          'annotations' => {
            'maintainers' => '[{"type":"Individual","name":"Testers"}]',
            'description' => 'Testing',
            'configmap.reloader.stakater.com/reload' => 'x-blue-cronjob',
            'secret.reloader.stakater.com/reload' =>  'x-blue-cronjob'
          }
        },
        'spec' => {
          'concurrencyPolicy' => 'Forbid',
          'failedJobsHistoryLimit' => 10,
          'schedule' => '*/1 * * * *'

        }
      }
      expect(k8s_resource(set, 'CronJob')).to eql(expected_cronjob)

      expected_config_map = {
        'apiVersion' => 'v1',
        'kind' => 'ConfigMap',
        'metadata' => {
          'name' => 'x-blue-cronjob',
          'namespace' => 'e1',
          'labels' => {
            'app.kubernetes.io/managed-by' => 'stacks',
            'stack' => 'mystack',
            'machineset' => 'x',
            'group' => 'blue',
            'app.kubernetes.io/instance' => 'blue',
            'app.kubernetes.io/part-of' => 'x',
            'app.kubernetes.io/component' => 'cronjob_service'
          }
        },
        'data' => {
          'config.properties' => <<EOL
port=8000

log.directory=/var/log/app
log.tags=["env:e1", "app:MyApplication", "instance:blue"]
EOL
        }
      }

      puts expected_config_map
      # expect(k8s_resource(set, 'ConfigMap')).to eql(expected_config_map)

      k8s_resources = set.to_k8s(app_deployer, dns_resolver, hiera_provider).first.resources
      k8s_resources.group_by { |r| r['metadata']['labels']['app.kubernetes.io/component'] }.each do |_component, resources|
        ordering = {}
        resources.each_with_index do |s, index|
          ordering[s['kind']] = index
        end
        if %w(ConfigMap CronJob).all? { |k| ordering.key? k }
          expect(ordering['ConfigMap']).to be < ordering['CronJob']
        end
      end
    end
  end
end
