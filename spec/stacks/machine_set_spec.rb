require 'stacks/test_framework'

describe 'Stacks::MachineSet' do
  describe_stack 'allows creation of secondary servers' do
    given do
      stack "funds" do
        virtual_appserver 'fundsapp' do
          self.instances = 1
          enable_secondary_site
        end
      end

      env 'env', :primary_site => 'mars', :secondary_site => 'jupiter' do
        instantiate_stack 'funds'
      end
    end
    it_stack 'should contain 1 server in each site' do |stack|
      stack.should have_host('env-fundsapp-001.mgmt.mars.net.local')
      stack.should have_host('env-fundsapp-001.mgmt.jupiter.net.local')
    end
  end
end
