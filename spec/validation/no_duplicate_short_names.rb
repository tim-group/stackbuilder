require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/inventory'
require 'stackbuilder/stacks/validation/validation'
require 'stackbuilder/stacks/validation/no_duplicate_short_names'

describe 'no_duplicate_short_names' do
  describe 'validator' do
    it 'should pass if there are no duplicate short names between services' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
          app_service 'app1'
          app_service 'app2'
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      Stacks::Inventory.new(prepped_inventory)
    end

    it 'should pass if there are no duplicate short names between environments' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
        env "e2", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      Stacks::Inventory.new(prepped_inventory)
    end

    it 'should fail if there are duplicate short names between services' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
          app_service 'applicationname1'
          app_service 'applicationname2'
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      expect do
        Stacks::Inventory.new(prepped_inventory, [Stacks::Validation::NoDuplicateShortName])
      end.to raise_error('Duplicate short_name \'applicationn\' in machine_sets named applicationname1, applicationname2')
    end

    it 'should fail if there are duplicate short names between services in different environments' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack1" do
          app_service 'applicationname1'
        end
        stack "mystack2" do
          app_service 'applicationname2'
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack1"
        end
        env "e2", :primary_site => 'space' do
          instantiate_stack "mystack2"
        end
      end
      expect do
        Stacks::Inventory.new(prepped_inventory, [Stacks::Validation::NoDuplicateShortName])
      end.to raise_error('Duplicate short_name \'applicationn\' in machine_sets named applicationname1, applicationname2')
    end

    it 'should not fail if there are duplicate short names between services but one of them is overridden to not be duplicate' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack1" do
          app_service 'applicationname1'
        end
        stack "mystack2" do
          app_service 'applicationname2' do
            self.short_name = 'appnm2'
          end
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack1"
        end
        env "e2", :primary_site => 'space' do
          instantiate_stack "mystack2"
        end
      end

      Stacks::Inventory.new(prepped_inventory, [Stacks::Validation::NoDuplicateShortName])
    end

    it 'should fail if there are duplicate short names between environments' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
          app_service 'applicationname'
        end
        env "environment1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
        env "environment2", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      expect do
        Stacks::Inventory.new(prepped_inventory, [Stacks::Validation::NoDuplicateShortName])
      end.to raise_error('Duplicate environment short_name \'env\' in environments environment1, environment2')
    end
  end
end
