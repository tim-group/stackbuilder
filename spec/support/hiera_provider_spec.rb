require 'stackbuilder/support/hiera_provider'
require 'tmpdir'
require 'open3'
require 'stackbuilder/stacks/factory'

class GivenHieradata
  def initialize(dir)
    @dir = dir
  end

  def file(name, &block)
    GivenFile.new(@dir, name).instance_eval(&block)
  end
end

class GivenFile
  def initialize(dir, filename)
    @dir = dir
    @filename = filename
  end

  def contents(contents)
    File.write(@dir + '/' + @filename, contents)
  end
end

describe Support::HieraProvider do
  before(:each) do
    @tmpdir = Dir.mktmpdir
    @local_path = Dir.mktmpdir
    @hiera_provider = Support::HieraProvider.new(:origin => @tmpdir, :local_path => @local_path)
  end

  after(:each) do
    FileUtils.remove_dir(@tmpdir)
    FileUtils.remove_dir(@local_path)
  end

  def given_hieradata(&block)
    Dir.chdir(@tmpdir) do
      system_call('git', 'init')
      File.write('unused_empty_file_to_ensure_git_commit', '')
      GivenHieradata.new(@tmpdir).instance_eval(&block)
      system_call('git', 'add', '--all')
      system_call('git', 'commit', '--message', 'initial commit')
    end
  end

  def system_call(*cmd)
    if cmd.last.is_a?(Hash)
      opts = cmd.pop.dup
    else
      opts = {}
    end

    _stdout_str, stderr_str, status = Open3.capture3(*cmd, opts)
    fail "System call failed - error: #{stderr_str}" if !status.success?
  end

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
        app_service "myk8sappservice", :kubernetes => true do
          self.application = 'MyK8sApplication'
          self.instances = 2
        end
      end
      env 'e1', :primary_site => 'space' do
        instantiate_stack "mystack"
      end
    end
  end

  it 'should raise exception if not passed a machineset' do
    environment = factory.inventory.find_environment('e1')
    expect { @hiera_provider.lookup(environment, 'anything') }.to raise_error(RuntimeError, /Hiera lookup requires a machineset/)
    stack = environment.find_stacks('mystack').first
    expect { @hiera_provider.lookup(stack, 'anything') }.to raise_error(RuntimeError, /Hiera lookup requires a machineset/)
    machinedef = stack.children.first.children.first
    expect { @hiera_provider.lookup(machinedef, 'anything') }.to raise_error(RuntimeError, /Hiera lookup requires a machineset/)
  end

  it "should raise exception if it can't clone the repo" do
    expect { Support::HieraProvider.new(:origin => "ce nest pas un directory").hieradata }.to raise_error(RuntimeError, /Unable to clone/)
  end

  it 'should raise exception if key not found and no default passed' do
    given_hieradata {}

    machineset = factory.inventory.find_environment('e1').find_stacks('mystack').first.k8s_machinesets['myk8sappservice']

    expect { @hiera_provider.lookup(machineset, 'key/that/does/not/exist') }.to raise_error(RuntimeError, /Could not find data item/)
  end

  it 'can look up hiera values' do
    given_hieradata do
      file 'logicalenv_e1.yaml' do
        contents <<EOF
---
first/key: 'the_value'
second/key: 42
EOF
      end
    end
    machineset = factory.inventory.find_environment('e1').find_stacks('mystack').first.k8s_machinesets['myk8sappservice']

    value = @hiera_provider.lookup(machineset, 'first/key')

    expect(value).to eq('the_value')
  end

  it 'can fall back to files lower in the hierarchy' do
    given_hieradata do
      file 'logicalenv_e1.yaml' do
        contents <<EOF
---
not/the/answer: 'RBBoT'
EOF
      end
      file 'common.yaml' do
        contents <<EOF
---
the/answer: 42
EOF
      end
    end
    machineset = factory.inventory.find_environment('e1').find_stacks('mystack').first.k8s_machinesets['myk8sappservice']

    value = @hiera_provider.lookup(machineset, 'the/answer')

    expect(value).to eq(42)
  end

  it 'returns default value if key not found in data files' do
    given_hieradata {}

    machineset = factory.inventory.find_environment('e1').find_stacks('mystack').first.k8s_machinesets['myk8sappservice']

    value = @hiera_provider.lookup(machineset, 'the/answer', 42)

    expect(value).to eq(42)
  end
end
