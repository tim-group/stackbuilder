require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'should provide 3 elasticsearch nodes by default' do
  given do
    stack "elasticsearch" do
      elasticsearch_cluster "logs"
    end

    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "elasticsearch"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'testing-logs-001.mgmt.space.net.local',
      'testing-logs-002.mgmt.space.net.local',
      'testing-logs-003.mgmt.space.net.local'
    ])
  end

  host("testing-logs-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::elasticsearch_node']['cluster_nodes'].sort).to eql([
      'testing-logs-001.space.net.local',
      'testing-logs-002.space.net.local',
      'testing-logs-003.space.net.local'
    ])
  end

  host("testing-logs-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::elasticsearch_node']['cluster_name']).to eql("logs")
  end

  host("testing-logs-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app']['dependencies']['elasticsearch_cluster_nodes'].sort).to eql([
      'testing-logs-001.space.net.local',
      'testing-logs-002.space.net.local',
      'testing-logs-003.space.net.local'
    ])
  end

  host("testing-logs-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app']['elasticsearch_cluster_name']).to eql("logs")
  end

  # check the basic config hasn't been overwritten
  host("testing-logs-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::http_app']['port']).to eql("8000")
  end
end

describe_stack 'should provide a default of 16GB of ram and 4 cpu cores' do
  given do
    stack "elasticsearch" do
      elasticsearch_cluster "logs" do
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "elasticsearch"
    end
  end

  host("testing-logs-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.shift[:ram]).to eql '16777216'
    expect(host.to_specs.shift[:vcpus]).to eql '4'
  end
end
