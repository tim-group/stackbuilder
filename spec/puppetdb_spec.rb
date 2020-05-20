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
    expect(host.to_specs.first[:networks]).to eql([:mgmt, :prod])
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
    expect(host.to_enc).to have_key('role::puppetdb')
    enc = host.to_enc['role::puppetdb']
    expect(enc['allowed_hosts']).to eql(['e1-puppetserver-001.mgmt.space.net.local'])
    expect(enc['version']).to eql('2.3.8-1puppetlabs1')
    expect(host.to_specs.shift[:availability_group]).to eql('e1-puppetdb')
  end
  it_stack 'should contain 1 puppetserver' do |stack|
    expect(stack).to have_hosts(['e1-puppetserver-001.mgmt.space.net.local', 'e1-puppetdb-001.mgmt.space.net.local'])
  end
end

describe_stack 'basic puppetdb_cluster with puppetserver_cluster and custom version' do
  given do
    stack 'puppetserver_cluster' do
      puppetserver_cluster 'puppetserver' do
        depend_on 'puppetdb'
      end
    end

    stack 'puppetdb_cluster' do
      puppetdb_cluster 'puppetdb' do
        self.version = 'foobar'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "puppetserver_cluster"
      instantiate_stack "puppetdb_cluster"
    end
  end

  host("e1-puppetdb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc).to have_key('role::puppetdb')
    enc = host.to_enc['role::puppetdb']
    expect(enc['allowed_hosts']).to eql(['e1-puppetserver-001.mgmt.space.net.local'])
    expect(enc['version']).to eql('foobar')
    expect(host.to_specs.shift[:availability_group]).to eql('e1-puppetdb')
  end
  it_stack 'should contain 1 puppetserver' do |stack|
    expect(stack).to have_hosts(['e1-puppetserver-001.mgmt.space.net.local', 'e1-puppetdb-001.mgmt.space.net.local'])
  end
end
