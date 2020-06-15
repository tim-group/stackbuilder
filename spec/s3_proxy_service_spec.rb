require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'
require 'test_classes'
require 'spec_helper'

describe 's3 proxy service' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e1-k8sapp-vip.earth.net.local' => '3.1.4.1',
                          'e2-s3proxy-001.earth.net.local' => '3.1.4.2',
                          'office-nexus-001.mgmt.lon.net.local' => '3.1.4.3',
                          'production-sharedproxy-001.earth.net.local' => '3.1.4.4',
                          'production-sharedproxy-002.earth.net.local' => '3.1.4.5')
  end
  let(:hiera_provider) do
    TestHieraProvider.new('stacks/application_credentials_selector' => 0)
  end

  it 'supports being depended on by a k8s app' do
    factory = eval_stacks do
      stack 'k8s_app' do
        app_service 'k8sapp', :kubernetes => true do
          self.application = 'example'
          self.maintainers = [person('Testers')]
          self.description = 'Testing'
          self.alerts_channel = 'test'
          self.startup_alert_threshold = '1h'
          depend_on 's3proxy', 'e2'
        end
      end
      stack 's3_proxy' do
        s3_proxy_service 's3proxy' do
          self.instances = 1
        end
      end

      env 'e1', :primary_site => 'earth' do
        instantiate_stack 'k8s_app'
      end
      env 'e2', :primary_site => 'earth' do
        instantiate_stack 's3_proxy'
      end
    end

    machine_sets = factory.inventory.find_environment('e1').definitions['k8s_app'].k8s_machinesets
    k8s = machine_sets['k8sapp'].to_k8s(app_deployer, dns_resolver, hiera_provider)

    expect(k8s.flat_map(&:resources).find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
      to match(/s3\.proxyhost=e2-s3proxy-001.earth.net.local/)

    expect(k8s.flat_map(&:resources).find { |s| s['kind'] == 'ConfigMap' }['data']['config.properties']).
      to match(/s3\.proxyport=80/)

    s3proxy_network_policy = k8s.flat_map(&:resources).find { |s| s['kind'] == 'NetworkPolicy' && s['metadata']['name'].match(/s3proxy/) }

    expect(s3proxy_network_policy['metadata']['name']).to eql('allow-out-to-e2-s3proxy-60145d4')
    expect(s3proxy_network_policy['metadata']['namespace']).to eql('e1')
    expect(s3proxy_network_policy['spec']['podSelector']['matchLabels']).to eql(
      "machineset" => "k8sapp",
      "group" => "blue",
      "app.kubernetes.io/component" => "app_service"
    )
    expect(s3proxy_network_policy['spec']['policyTypes']).to eql(['Egress'])
    expect(s3proxy_network_policy['spec']['egress'].size).to eq(1)
    expect(s3proxy_network_policy['spec']['egress'].first['to'].size).to eq(1)
    expect(s3proxy_network_policy['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.2/32' })
    expect(s3proxy_network_policy['spec']['egress'].first['ports'].size).to eq(1)
    expect(s3proxy_network_policy['spec']['egress'].first['ports'].first['protocol']).to eql('TCP')
    expect(s3proxy_network_policy['spec']['egress'].first['ports'].first['port']).to eq(80)
  end

  it 'blows up if it has more than one child instance' do
    expect do
      eval_stacks do
        stack 'k8s_app' do
          app_service 'k8sapp', :kubernetes => true do
            self.application = 'example'
            self.maintainers = [person('Testers')]
            self.description = 'Testing'
            depend_on 's3proxy', 'e2'
          end
        end
        stack 's3_proxy' do
          s3_proxy_service 's3proxy' do
            self.instances = 2
          end
        end

        env 'e1', :primary_site => 'earth' do
          instantiate_stack 'k8s_app'
        end
        env 'e2', :primary_site => 'earth' do
          instantiate_stack 's3_proxy'
        end
      end
    end.to raise_error(/does not support more than one instance/)
  end
end
