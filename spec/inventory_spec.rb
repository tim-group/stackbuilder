require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/inventory'
require 'stackbuilder/stacks/validation/validation'

class Stacks::Validation::Pass < Stacks::Validation::Validation
  def validate(_stacks)
    @passed = true
  end
end

class Stacks::Validation::Fail < Stacks::Validation::Validation
  def validate(_stacks)
    @passed = false
  end

  def failure_output
    "This validator always fails"
  end
end

describe 'inventory' do
  describe 'initialisation' do
    it 'should run validators against a stack' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      Stacks::Inventory.new(prepped_inventory, [])
    end

    it 'should not raise errors if validators run successfully' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      Stacks::Inventory.new(prepped_inventory, [
        Stacks::Validation::Pass,
        Stacks::Validation::Pass,
        Stacks::Validation::Pass
      ])
    end

    it 'should raise an error if any validators fail' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      expect do
        Stacks::Inventory.new(prepped_inventory, [
          Stacks::Validation::Pass,
          Stacks::Validation::Fail,
          Stacks::Validation::Pass
        ])
      end.to raise_error("This validator always fails")
    end

    it 'should raise an error with multiple lines if multiple validators fail' do
      prepped_inventory = Stacks::Inventory.prepare_inventory_from do
        stack "mystack" do
        end
        env "e1", :primary_site => 'space' do
          instantiate_stack "mystack"
        end
      end
      expect do
        Stacks::Inventory.new(prepped_inventory, [
          Stacks::Validation::Pass,
          Stacks::Validation::Fail,
          Stacks::Validation::Fail
        ])
      end.to raise_error("This validator always fails\nThis validator always fails")
    end
  end
end
