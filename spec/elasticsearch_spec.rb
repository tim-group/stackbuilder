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
    expect(host.to_enc.key?('role::elasticsearch_node')).to eql(true)
  end
end
