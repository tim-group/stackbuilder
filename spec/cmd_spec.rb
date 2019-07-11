require 'stackbuilder/stacks/factory'
require 'stackbuilder/support/cmd'
require 'stacks/test_framework'

describe 'compile' do
  def eval_stacks(&block)
    Stacks::Factory.new(Stacks::Inventory.from(&block))
  end

  # using this instead of the rspec output() matcher to limit the number of times we have to run things.
  # If we used the output matcher the command needs to be run for the positive and negative assertions of a test,
  # which doubles the runtime of the tests.
  def capture_stdout(&block)
    out = StringIO.new
    old_stdout = $stdout
    $stdout = out

    block.call

    $stdout = old_stdout
    out.string
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
    out = capture_stdout do
      cmd = CMD.new(factory, nil, nil)
      cmd.compile nil
    end

    expect(out).to match(/\be1-myappservice-001.mgmt.space.net.local:.*
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
                         /mx)
  end

  it 'prints enc and spec for a stack' do
    out = capture_stdout do
      cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'mystack')
      cmd.compile nil
    end

    expect(out).to match(/\be1-myappservice-001.mgmt.space.net.local:.*
                         \benc:.*
                         \bspec:.*
                         \be1-myappservice-002.mgmt.space.net.local:.*
                         \benc:.*
                         \bspec:.*
                         \be1-myrelatedappservice-001.mgmt.space.net.local:.*
                         \benc:.*
                         \bspec:.*
                         /mx)

    expect(out).not_to match(/\be2-myotherappservice-001.mgmt.space.net.local:.*
                             \benc:.*
                             \bspec:.*
                             /mx)
  end

  it 'prints enc and spec for a specific machineset' do
    out = capture_stdout do
      cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'myappservice')
      cmd.compile nil
    end

    expect(out).to match(/\be1-myappservice-001.mgmt.space.net.local:.*
                         \benc:.*
                         \bspec:.*
                         \be1-myappservice-002.mgmt.space.net.local:.*
                         \benc:.*
                         \bspec:.*
                         /mx)

    expect(out).not_to match(/\be2-myotherappservice-001.mgmt.space.net.local:
                             |
                             \be1-myrelatedappservice-001.mgmt.space.net.local:
                             /mx)
  end

  it 'prints enc and spec for a specific machine' do
    out = capture_stdout do
      cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'e1-myappservice-001.mgmt.space.net.local')

      cmd.compile nil
    end

    expect(out).to match(/\be1-myappservice-001.mgmt.space.net.local:.*
                                         \benc:.*
                                         \bspec:.*
                                         /mx)

    expect(out).not_to match(/\be1-myappservice-002.mgmt.space.net.local:
                                             |
                                             \be1-myrelatedappservice-001.mgmt.space.net.local:
                                             |
                                             \be2-myotherappservice-001.mgmt.space.net.local:
                                             /mx)
  end

  it 'fails if the name is not found' do
    cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'notfound')

    expect { cmd.compile nil }.to raise_error('Entity not found')
  end

  it 'fails if more than one entity is found' do
    factory = eval_stacks do
      stack "mystack" do
        app_service "dupedservice" do
          self.application = 'MyApplication'
        end
      end
      stack "myotherstack" do
        app_service "dupedservice" do
          self.application = 'MyOtherApplication'
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
        instantiate_stack "myotherstack"
      end
    end

    cmd = CMD.new(factory, factory.inventory.find_environment('e1'), 'dupedservice')

    expect { cmd.compile nil }.to raise_error('Too many entities found')
  end
end
