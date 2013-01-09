require 'set'
require 'stacks/environment'
require 'pp'

RSpec::Matchers.define :produce_a_tree_like do |expected_tree|
  match do |environment|
    result = environment.visit({}) do |tree, machine_def, block|
      new_tree = tree[machine_def.name] = {}
      machine_def.children.each do |child|
        child.visit(new_tree, &block)
      end
      tree
    end
    pp result
    result == expected_tree
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


describe "ENC::DSL" do

  before do
    extend Stacks
    env "blah" do
      loadbalancer "lb"
      virtualservice "appx"
      virtualservice "dbx"
    end
  end

  it 'I can traverse a tree of machine definitions' do
    environments["blah"].should produce_a_tree_like(
      "blah"=>{
      "blah-lb-001"=>{},
      "blah-lb-002"=>{},
      "appx"=>{
      "blah-appx-001"=>{},
      "blah-appx-002"=>{}
    },
      "dbx"=>{
      "blah-dbx-001"=>{},
      "blah-dbx-002"=>{}
    }})
  end

  it 'produces a list of machines under any level' do
    environments["blah"].machines.size.should eql(6)
    environments["blah"].children[0].machines.size.should eql(2)
  end
end
