require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe 'Stacks::MachineSet' do
  describe_stack 'allows creation of secondary servers' do
    given do
      stack "funds" do
        virtual_appserver 'fundsapp' do
          self.instances = 1
          @enable_secondary_site = true
        end
      end

      env 'env', :primary_site => 'mars', :secondary_site => 'jupiter' do
        instantiate_stack 'funds'
      end
    end
    it_stack 'should contain 1 server in each site' do |stack|
      expect(stack).to have_host('env-fundsapp-001.mgmt.mars.net.local')
      expect(stack).to have_host('env-fundsapp-001.mgmt.jupiter.net.local')
    end
  end
  describe_stack 'provides an allowed host mechanism that can be used by virtual_appservers' do
    given do
      stack "mystack" do
        virtual_appserver "x" do
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
  describe_stack 'provides an allowed host mechanism that can be used by standalone_appservers' do
    given do
      stack "mystack" do
        standalone_appserver "x" do
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
