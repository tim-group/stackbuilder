require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/cmd'
require 'stacks/test_framework'

describe 'compile' do
  def eval_stacks(&block)
    Stacks::Factory.new(Stacks::Inventory.from(&block))
  end

  it 'prints spec and enc for a specific machine' do
    factory = eval_stacks do
      stack "mystack" do
        app_service "x" do
          self.application = 'MyApplication'
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end

    cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'e1-x-001.mgmt.space.net.local')

    expect { cmd.compile nil }.to output(/\benc:/).to_stdout
    expect { cmd.compile nil }.to output(/\bspec:/).to_stdout
  end

  it 'prints spec and enc for everything' do
    factory = eval_stacks do
      stack "mystack" do
        app_service "x" do
          self.application = 'MyApplication'
        end
      end
      stack "myotherstack" do
        app_service "y" do
          self.application = 'MyOtherApplication'
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
      end
      env 'e2', :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end

    cmd = CMD.new(factory, nil, nil)

    expect { cmd.compile nil }.to output(/\benc:/).to_stdout
    expect { cmd.compile nil }.to output(/\bspec:/).to_stdout
  end
end
