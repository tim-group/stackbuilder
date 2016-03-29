require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'basic puppetserver_cluster' do
  given do
    stack 'puppetserver_cluster' do
      puppetserver_cluster 'puppetserver' do
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "puppetserver_cluster"
    end
  end

  host("e1-puppetserver-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.first[:template]).to eql('puppetserver')
    enc = host.to_enc['role::puppetserver']
    expect(enc['storedconfigs']).to eql(false)
    expect(enc['puppetdb_server']).to eql(nil)
  end
  it_stack 'should contain 1 puppetserver' do |stack|
    expect(stack).to have_hosts(['e1-puppetserver-001.mgmt.space.net.local'])
  end
end

describe_stack 'basic puppetserver_cluster with puppetdb' do
  given do
    stack 'puppetserver_cluster' do
      puppetserver_cluster 'puppetserver' do
        depend_on 'puppetdb'
      end
    end

    stack 'puppetdb_cluster' do
      puppetdb_cluster 'puppetdb' do
        @instances = 2
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "puppetserver_cluster"
      instantiate_stack "puppetdb_cluster"
    end
  end

  host("e1-puppetserver-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::puppetserver']
    expect(enc['storedconfigs']).to eql(true)
    expect(enc['puppetdb_server']).to eql('e1-puppetdb-001.mgmt.space.net.local')
    expect(host.to_specs.first[:template]).to eql('puppetserver')
    expect(host.to_specs.shift[:availability_group]).to eql('e1-puppetserver')
  end
  it_stack 'should contain 1 puppetserver' do |stack|
    expect(stack).to have_hosts([
      'e1-puppetserver-001.mgmt.space.net.local',
      'e1-puppetdb-001.mgmt.space.net.local',
      'e1-puppetdb-002.mgmt.space.net.local'
    ])
  end
end

describe_stack 'puppetservers get persistent /var/lib/puppet/ssl' do
  given do
    stack 'puppetserver_cluster' do
      puppetserver_cluster 'puppetserver' do
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "puppetserver_cluster"
    end
  end

  host("e1-puppetserver-001.mgmt.space.net.local") do |host|
    specs = host.to_specs.first
    expect(specs[:hostname]).to eql('e1-puppetserver-001')
    expect(specs[:storage][:'/var/lib/puppet/ssl']).to eql(:type       => 'data',
                                                           :size       => '1G',
                                                           :persistent => true)
  end
end

describe_stack 'allow override of persistent /var/lib/puppet/ssl' do
  given do
    stack 'puppetserver_cluster' do
      puppetserver_cluster 'puppetserver' do
        each_machine(&:dont_persist_certs)
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "puppetserver_cluster"
    end
  end

  host("e1-puppetserver-001.mgmt.space.net.local") do |host|
    specs = host.to_specs.first
    expect(specs[:hostname]).to eql('e1-puppetserver-001')
    expect(specs[:storage][:'/var/lib/puppet/ssl']).to eql(:type       => 'data',
                                                           :size       => '1G',
                                                           :persistent => false)
  end
end
