require 'stackbuilder/stacks/factory'
require 'test_classes'
require 'spec_helper'

describe 'kubernetes' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e1-x-vip.space.net.local' => '3.1.4.1',
                          'e1-app1-001.space.net.local' => '3.1.4.1',
                          'e1-app1-002.space.net.local' => '3.1.4.2')
  end
  let(:hiera_provider) { TestHieraProvider.new('the_hiera_key' => 'the_hiera_value') }

  describe 'machine sets' do
    it 'can be created' do
      factory = eval_stacks do
        stack "mystack" do
          standalone_app_service "x", :kubernetes => true do
            self.application = 'MyApplication'
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end

      mystack = factory.inventory.find_environment('e1').definitions['mystack']
      expect(mystack.definitions.size).to eq(0)
      expect(mystack.k8s_machinesets.size).to eq(1)
    end
  end
end
