require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/cmd'
require 'stacks/test_framework'

describe 'compile' do
  def eval_stacks(&block)
    Stacks::Factory.new(Stacks::Inventory.from(&block))
  end

  let(:factory) do
    eval_stacks do
      stack "mystack" do
        app_service "myappservice" do
          self.application = 'MyApplication'
          self.instances = 2
        end
        app_service "myrelatedappservice" do
          self.application = 'MyRelatedApplication'
          self.instances = 1
        end
      end
      stack "myotherstack" do
        app_service "myotherappservice" do
          self.application = 'MyOtherApplication'
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
      end
      env 'e2', :primary_site => 'space' do
        instantiate_stack "myotherstack"
      end
    end
  end

  it 'prints enc and spec for everything' do
    cmd = CMD.new(factory, nil, nil)

    expect { cmd.compile nil }.to output(/\be1-myappservice-001.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         \be1-myappservice-002.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         \be1-myrelatedappservice-001.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         \be2-myotherappservice-001.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         /mx).to_stdout
  end

  it 'prints enc and spec for a stack' do
    cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'mystack')

    expect { cmd.compile nil }.to output(/\be1-myappservice-001.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         \be1-myappservice-002.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         \be1-myrelatedappservice-001.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         /mx).to_stdout

    expect { cmd.compile nil }.not_to output(/\be2-myotherappservice-001.mgmt.space.net.local:.*
                                             \benc:.*
                                             \bspec:.*
                                             /mx).to_stdout
  end

  it 'prints enc and spec for a specific machineset' do
    cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'myappservice')

    expect { cmd.compile nil }.to output(/\be1-myappservice-001.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         \be1-myappservice-002.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         /mx).to_stdout

    expect { cmd.compile nil }.not_to output(/\be2-myotherappservice-001.mgmt.space.net.local:
                                             |
                                             \be1-myrelatedappservice-001.mgmt.space.net.local:
                                             /mx).to_stdout
  end

  it 'prints enc and spec for a specific machine' do
    cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'e1-myappservice-001.mgmt.space.net.local')

    expect { cmd.compile nil }.to output(/\be1-myappservice-001.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         /mx).to_stdout

    expect { cmd.compile nil }.not_to output(/\be1-myappservice-002.mgmt.space.net.local:
                                             |
                                             \be1-myrelatedappservice-001.mgmt.space.net.local:
                                             |
                                             \be2-myotherappservice-001.mgmt.space.net.local:
                                             /mx).to_stdout
  end

  it 'fails if the name is not found' do
    cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'notfound')

    expect { cmd.compile nil }.to raise_error('Entity not found')
  end
end
