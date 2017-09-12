require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'kafka' do
  given do
    stack "kafka_stack" do
      kafka_cluster "kafka" do |cluster|
        cluster.instances = 3
        cluster.enable_secondary_site = true
      end
    end

    env "e1", :primary_site => "space", :secondary_site => "moon" do
      instantiate_stack "kafka_stack"
    end
  end

  host("e1-kafka-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::kafka_server']['clusternodes'].sort).to include(
      "e1-kafka-001.moon.net.local", "e1-kafka-002.moon.net.local",
      "e1-kafka-002.space.net.local", "e1-kafka-003.moon.net.local", "e1-kafka-003.space.net.local")
    expect(host.to_enc['role::kafka_server']['clusternodes'].sort).not_to include('e1-kafka-001.mgmt.space.net.local')
  end
end
