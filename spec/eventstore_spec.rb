require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'eventstore' do
  given do
    stack "eventstore_stack" do
      eventstore_cluster "eventstore" do |cluster|
        cluster.instances = 3
        cluster.enable_secondary_site = true
      end
    end

    env "e1", :primary_site => "space", :secondary_site => "moon" do
      instantiate_stack "eventstore_stack"
    end
  end

  host("e1-eventstore-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::eventstore_server']['clusternodes'].sort).to include(
      "e1-eventstore-001.moon.net.local", "e1-eventstore-002.moon.net.local",
      "e1-eventstore-002.space.net.local", "e1-eventstore-003.moon.net.local", "e1-eventstore-003.space.net.local")
    expect(host.to_enc['role::eventstore_server']['clusternodes'].sort).not_to include('e1-eventstore-001.mgmt.space.net.local')
  end
end
