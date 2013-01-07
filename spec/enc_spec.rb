require 'set'
require 'stacks/environment'
require 'pp'

RSpec::Matchers.define :have_machines_named do |expected_machine_names|

  match do |environment|
    actual_machines = environment.machines.map {|machine|machine.hostname}
    actual_machines.to_set.eql?(expected_machine_names.to_set)
  end

  failure_message_for_should do |environment|
     actual_machines = environment.machines.map {|machine|machine.hostname}

     pp expected_machine_names.to_set

     pp actual_machines.to_set

     "expected environment to contain #{expected_machine_names} but got #{actual_machines.to_set.to_a}"
  end

  description do
    "expecting #{actual_machines.to_set} to be the same as #{expected_machines_names}"
  end

end


describe "ENC::DSL" do
  it 'generates an entry for all environments' do
    extend Stacks
    env "blah" do
      loadbalancer "lb"
      virtualservice "appx"
      virtualservice "dbx"
    end

    generate_machines()

    environments["blah"].should have_machines_named(["blah-lb-001",
                                                    "blah-lb-002",
                                                    "blah-appx-001",
                                                    "blah-appx-002",
                                                    "blah-dbx-001",
                                                    "blah-dbx-002"])
  end

  it 'I can iterate over stacks' do
  end

  it 'I can iterate over stacks and definitions' do
  end
end
