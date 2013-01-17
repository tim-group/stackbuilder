require 'set'
require 'stacks/stack'
require 'stacks/environment'
require 'pp'

module TestMethods
  def tree
    tree = {}
    children.each do |child|
      tree[child.name] = child.tree
    end
    return tree
  end
end

RSpec::Matchers.define :produce_a_tree_like do |expected_tree|
  match do |environment|
    environment.recursive_extend(TestMethods)
    environment.tree == expected_tree
  end
  failure_message_for_should do |environment|
    "expected #{environment} to match #{expected_tree}"
  end
end

RSpec::Matchers.define :have_machines_named do |expected_machine_names|
  match do |environment|
    actual_machines = environment.machines.map {|machine|machine.hostname}
    actual_machines.to_set.eql?(expected_machine_names.to_set)
  end

  failure_message_for_should do |environment|
    actual_machines = environment.machines.map {|machine|machine.hostname}
    "expected environment to contain #{expected_machine_names} but got #{actual_machines.to_set.to_a}"
  end

  description do
    "expecting #{actual_machines.to_set} to be the same as #{expected_machines_names}"
  end

end

RSpec::Matchers.define :contain_machines do |expected_specs|
  match do |container|

    pp container


    true
  end
end


describe Stacks::DSL do

  before do
    extend Stacks::DSL
    stack "blah" do
      virtualservice "appx"
      virtualservice "dbx"
    end
    env "ci", :primary=>"st", :secondary=>"bs"
  end

  it 'binds to configuration from the environment' do
    bind_to('ci')
    appx = stacks["blah"]["appx"]
    appx.to_specs.should eql([{
      :hostname => "ci-appx-001",
      :domain => "st.net.local",
      :fabric => "st",
      :group => "ci-appx",
      :template => "copyboot",
      :networks => ["mgmt"]
    },
      {
      :hostname => "ci-appx-002",
      :domain => "st.net.local",
      :fabric => "st",
      :group => "ci-appx",
      :template => "copyboot",
      :networks => ["mgmt"]
    }])
  end

end
