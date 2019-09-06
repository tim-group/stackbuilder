require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/inventory'
require 'stackbuilder/stacks/validation/validation'
require 'stackbuilder/stacks/validation/service_names_unique_across_stacks'

describe 'service names unique across stacks' do
  describe 'validator' do
    it 'should pass if there are no services with the same name in multiple stacks' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
          app_service 'app1'
        end
        stack 'myotherstack' do
          app_service 'app2'
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
          instantiate_stack "myotherstack"
        end
        env "e2", :primary_site => 'space' do
          instantiate_stack "mystack"
          instantiate_stack "myotherstack"
        end
      end
      Stacks::Inventory.new(prepped_inventory)
    end

    it 'should fail if there are duplicate service names across stacks' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
          app_service 'app1'
        end
        stack 'myotherstack' do
          app_service 'app1'
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
          instantiate_stack "myotherstack"
        end
      end
      expect do
        Stacks::Inventory.new(prepped_inventory, [Stacks::Validation::ServiceNamesUniqueAcrossStacks])
      end.to raise_error('Duplicate service \'app1\' in stacks \'mystack\', \'myotherstack\'')
    end

    it 'should fail if there are duplicate service names across stacks including k8s services' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
          app_service 'app1'
        end
        stack 'myotherstack' do
          app_service 'app1', :kubernetes => true
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
          instantiate_stack "myotherstack"
        end
      end
      expect do
        Stacks::Inventory.new(prepped_inventory, [Stacks::Validation::ServiceNamesUniqueAcrossStacks])
      end.to raise_error('Duplicate service \'app1\' in stacks \'mystack\', \'myotherstack\'')
    end
  end
end
