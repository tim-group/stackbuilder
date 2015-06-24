require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'eventstore' do
  given do
    stack "eventstore_stack" do
      eventstore "eventstore" do |cluster|
        cluster.instances = 3
        cluster.enable_secondary_site = true
      end
    end

    env "e1", primary_site: "space", secondary_site: "moon" do
      instantiate_stack "eventstore_stack"
    end
  end

  host("e1-eventstore-001.mgmt.space.net.local") do |host|
    host.to_enc['role::eventstore_server']['clusternodes'].sort.should eql(
      ["e1-eventstore-001.moon.net.local", "e1-eventstore-001.space.net.local", "e1-eventstore-002.moon.net.local",
       "e1-eventstore-002.space.net.local", "e1-eventstore-003.moon.net.local", "e1-eventstore-003.space.net.local"].
        sort)
  end
end
