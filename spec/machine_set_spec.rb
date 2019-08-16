require 'stackbuilder/stacks/factory'
require 'test_classes'
require 'spec_helper'

describe 'machine_set' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:dns_resolver) do
    MyTestDnsResolver.new(
      'e1-app1-vip.space.net.local' => '3.4.5.6',
      'production-sharedproxy-001.space.net.local' => '3.4.5.7',
      'production-sharedproxy-002.space.net.local' => '3.4.5.8',
      'office-nexus-001.mgmt.lon.net.local' => '3.4.5.9')
  end
  let(:hiera_provider) { TestHieraProvider.new('the_hiera_key' => 'the_hiera_value') }

  describe 'allow_outbound_connection' do
    it 'should fail if the machine_set isn\'t a kubernetes enabled machine_set' do
      expect do
        eval_stacks do
          stack 'test_stack' do
            app_service 'app1' do
              allow_outbound_to 'somewhere', '1.2.3.4/32', [80, 443]
            end
          end
          env 'e1', :primary_site => 'space' do
            instantiate_stack 'test_stack'
          end
        end
      end.to raise_error('Allowing outbound connections is only supported if kubernetes is enabled for this machine_set')
    end
    it 'should create kubernetes egress resources' do
      factory = eval_stacks do
        stack 'test_stack' do
          app_service 'app1', :kubernetes => true do
            self.maintainers = [person('Testers')]
            self.description = 'Testing'

            self.application = 'app'
            allow_outbound_to 'somewhere', '1.2.3.4/32', [80, 443]
          end
        end
        env 'e1', :primary_site => 'space' do
          instantiate_stack 'test_stack'
        end
      end

      machine_sets = factory.inventory.find_environment('e1').definitions['test_stack'].k8s_machinesets
      app1_machine_set = machine_sets['app1']
      network_policies = app1_machine_set.to_k8s(app_deployer, dns_resolver, hiera_provider).resources.select do |policy|
        policy['kind'] == "NetworkPolicy"
      end
      expect(network_policies.size).to eq(3)
      expect(network_policies.first['metadata']['name']).to eql('allow-app1-out-to-somewhere-on-ports-80-443')
      expect(network_policies.first['metadata']['namespace']).to eql('e1')
      expect(network_policies.first['spec']['podSelector']['matchLabels']['app.kubernetes.io/instance']).to eql('e1-test_stack-app')
      expect(network_policies.first['spec']['policyTypes']).to eql(['Egress'])

      egress = network_policies.first['spec']['egress']
      expect(egress.size).to be(1)
      expect(egress.first['to'].size).to be(1)
      expect(egress.first['ports'].size).to be(2)
      expect(network_policies.first['spec']['egress'].first['to']).to include('ipBlock' => { 'cidr' => '1.2.3.4/32' })
      expect(egress.first['ports'].first['protocol']).to eql('TCP')
      expect(egress.first['ports'].first['port']).to be(80)
      expect(egress.first['ports'].last['protocol']).to eql('TCP')
      expect(egress.first['ports'].last['port']).to be(443)
    end
  end
  describe 'short_name' do
    it 'should default to the first 12 characters of the name of the machine_set' do
      factory = eval_stacks do
        stack 'mystack' do
          app_service 'supercalifragilisticexpialidocious' do
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack 'mystack'
        end
      end
      machine_set = factory.inventory.find_environment('e1').definitions['mystack'].definitions['supercalifragilisticexpialidocious']
      expect(machine_set.short_name).to eql('supercalifra')
    end

    it 'should default to the name of the machine_set if the machine_set name is less than 12 characters' do
      factory = eval_stacks do
        stack 'mystack' do
          app_service 'app' do
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack 'mystack'
        end
      end
      machine_set = factory.inventory.find_environment('e1').definitions['mystack'].definitions['app']
      expect(machine_set.short_name).to eql('app')
    end

    it 'should raise an error if you try to set the short_name to more than 12 characters' do
      expect do
        eval_stacks do
          stack 'mystack' do
            app_service 'app' do
              set_short_name 'supercalifragilisticexpialidocious'
            end
          end
          env "e1", :primary_site => 'space' do
            instantiate_stack 'mystack'
          end
        end
      end.to raise_error('The short name of a machine_set must be less than twelve characters. You tried to set_short_name of machine_set \'app\' in environment \'e1\' to \'supercalifragilisticexpialidocious\'')
    end
  end
end
