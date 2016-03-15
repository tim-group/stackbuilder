require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'basic dev puppetdb without cname' do
  given do
    stack 'puppetdb_cluster' do
      puppetdb_cluster 'puppetdb' do
        each_machine do |machine|
          machine.cnames = {}
        end
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "puppetdb_cluster"
    end
  end

  host("e1-puppetdb-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.first[:cnames]).to eql({})
  end
end

describe_stack 'basic puppetdb_cluster with puppetserver_cluster' do
  given do
    stack 'puppetserver_cluster' do
      puppetserver_cluster 'puppetserver' do
        depend_on 'puppetdb'
      end
    end

    stack 'puppetdb_cluster' do
      puppetdb_cluster 'puppetdb'
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "puppetserver_cluster"
      instantiate_stack "puppetdb_cluster"
    end
  end

  host("e1-puppetdb-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['timgroup::puppetdb']
    expect(enc['allowed_hosts']).to eql(['e1-puppetserver-001.mgmt.space.net.local'])
    expect(host.to_specs.first[:cnames][:mgmt]).to eql("puppetdb" => "e1-puppetdb-001.mgmt.space.net.local")
  end
  it_stack 'should contain 1 puppetserver' do |stack|
    expect(stack).to have_hosts(['e1-puppetserver-001.mgmt.space.net.local', 'e1-puppetdb-001.mgmt.space.net.local'])
  end
end
