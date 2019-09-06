require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'
require 'test_classes'

describe_stack 'test enc of the mail servers' do
  given do
    stack "lb" do
      loadbalancer_service
    end

    stack 'mail_stack' do
      mail_service 'mail' do
        case environment.name
        when 'oymigration'
          allow_host '172.16.0.0/21'
        end
      end
    end

    env "oymigration", :primary_site => "oy" do
      instantiate_stack "lb"
      instantiate_stack "mail_stack"
    end
  end

  # OY Master
  host("oymigration-mail-001.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    expect(enc['server']).to eql("postfix" => false)
    expect(enc['role::mail_server2']['allowed_hosts'].sort).to eql([
      '172.16.0.0/21'
    ])
    expect(enc['role::mail_server2']['vip_fqdns'].sort).to eql([
      'oymigration-mail-vip.mgmt.oy.net.local', 'oymigration-mail-vip.oy.net.local'
    ])
    expect(enc['role::mail_server2']['dependant_instances'].sort).to eql([
      'oymigration-lb-001.mgmt.oy.net.local',
      'oymigration-lb-001.oy.net.local',
      'oymigration-lb-002.mgmt.oy.net.local',
      'oymigration-lb-002.oy.net.local'
    ])
    expect(enc['role::mail_server2']['participation_dependant_instances']).to eql([
      'oymigration-lb-001.mgmt.oy.net.local',
      'oymigration-lb-001.oy.net.local',
      'oymigration-lb-002.mgmt.oy.net.local',
      'oymigration-lb-002.oy.net.local'
    ])
    expect(enc['role::mail_server2']['vip_networks'].sort).to eql(%w(mgmt prod))
  end
end

describe 'kubernetes' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:failing_app_deployer) { TestAppDeployer.new(nil) }
  let(:dns_resolver) do
    MyTestDnsResolver.new(
      'e1-x-vip.space.net.local' => '1.2.3.4',
      'production-sharedproxy-001.space.net.local' => '1.2.3.5',
      'production-sharedproxy-002.space.net.local' => '1.2.3.6',
      'e1-mail-vip.mgmt.space.net.local' => '1.2.3.7',
      'e1-mail-vip.space.net.local' => '1.2.3.8',
      'office-nexus-001.mgmt.lon.net.local' => '1.2.3.9'
    )
  end
  let(:hiera_provider) do
    TestHieraProvider.new({})
  end
  describe 'app service' do
    describe 'depending on a mail server service' do
      it 'should provide an smtp server for the application config and correct network policies/firewall rules' do
        factory = eval_stacks do
          stack "mystack" do
            mail_service "mail" do
            end
            app_service "x", :kubernetes => true do
              self.maintainers = [person('Testers')]
              self.description = 'Testing'

              self.application = 'MyApplication'
              self.jvm_args = '-XX:+UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled'
              depend_on 'mail'
            end
          end

          env "e1", :primary_site => 'space' do
            instantiate_stack "mystack"
          end
        end

        k8s_machine_sets = factory.inventory.find_environment('e1').definitions['mystack'].k8s_machinesets
        app_service_k8s_resources = k8s_machine_sets['x'].to_k8s(app_deployer, dns_resolver, hiera_provider)
        config_maps = app_service_k8s_resources.flat_map(&:resources).select do |policy|
          policy['kind'] == "ConfigMap"
        end
        network_policies = app_service_k8s_resources.flat_map(&:resources).select do |policy|
          policy['kind'] == "NetworkPolicy"
        end

        expect(config_maps.size).to eql(1)
        expect(config_maps.first['data']['config.properties']).to include('smtp.server=e1-mail-vip.space.net.local:25')

        expect(network_policies.size).to eq(2)
        expect(network_policies.first['metadata']['name']).to eql('allow-x-out-to-e1-mail-25')
        expect(network_policies.first['spec']['egress'].size).to eq(1)
        expect(network_policies.first['spec']['egress'].first['to'].size).to eq(1)
        expect(network_policies.first['spec']['egress'].first['ports'].size).to eq(1)
        expect(network_policies.first['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '1.2.3.8/32' })
        expect(network_policies.first['spec']['egress'].first['ports'].first['protocol']).to eql('TCP')
        expect(network_policies.first['spec']['egress'].first['ports'].first['port']).to eq(25)

        machine_sets = factory.inventory.find_environment('e1').definitions['mystack'].definitions
        mail_server_enc = machine_sets['mail'].children.first.to_enc
        expect(mail_server_enc["role::mail_server2"]['allow_kubernetes_clusters']).to eql(['space'])
      end
    end
  end
end
