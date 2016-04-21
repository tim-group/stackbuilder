require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'should provide default set of elasticsearch nodes' do
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
      'testing-logs-master-001.mgmt.space.net.local',
      'testing-logs-master-002.mgmt.space.net.local',
      'testing-logs-master-003.mgmt.space.net.local',
      'testing-logs-data-001.mgmt.space.net.local',
      'testing-logs-data-002.mgmt.space.net.local',
      'testing-logs-data-003.mgmt.space.net.local',
      'testing-logs-data-004.mgmt.space.net.local'
    ])
  end

  host("testing-logs-master-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::elasticsearch::master']['master_nodes'].sort).to eql([
      'testing-logs-master-002.space.net.local',
      'testing-logs-master-003.space.net.local'
    ])
  end

  host("testing-logs-master-002.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::elasticsearch::master']['master_nodes'].sort).to eql([
      'testing-logs-master-001.space.net.local',
      'testing-logs-master-003.space.net.local'
    ])
    expect(host.to_enc['role::elasticsearch::master'].keys.sort).to eql(%w(
      cluster_name
      master_nodes
      minimum_master_nodes
      version
      vip_fqdn
    ))
    expect(host.to_enc['role::elasticsearch::master']['marvel_target']).to eql(nil)

    expect(host.to_enc['role::elasticsearch::master']['minimum_master_nodes']).to eql(2)
  end

  host("testing-logs-master-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::elasticsearch::master']['cluster_name']).to eql("testing-logs")
  end

  host("testing-logs-data-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::elasticsearch::data']['master_nodes'].sort).to eql([
      'testing-logs-master-001.space.net.local',
      'testing-logs-master-002.space.net.local',
      'testing-logs-master-003.space.net.local'
    ])
  end
end

describe_stack 'should provide default set of elasticsearch nodes with marvel target' do
  given do
    stack "elasticsearch" do
      elasticsearch_cluster "logs" do
        self.marvel_target = 'foobar'
        self.master_nodes = 1
      end
    end

    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "elasticsearch"
    end
  end

  host("testing-logs-master-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::elasticsearch::master'].keys.sort).to eql(%w(
      cluster_name
      marvel_target
      master_nodes
      minimum_master_nodes
      version
      vip_fqdn
    ))

    expect(host.to_enc['role::elasticsearch::master']['marvel_target']).to eql('testing-logs-vip.foobar.net.local')

    expect(host.to_enc['role::elasticsearch::master']['minimum_master_nodes']).to eql(1)
  end
end
