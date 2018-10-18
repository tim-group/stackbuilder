require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'kibana server enc is correct' do
  given do
    stack 'kibana_stack' do
      kibana do
        depend_on 'elasticsearch-data'
      end
      elasticsearch_data 'elasticsearch-data'
      loadbalancer_service
    end

    env 'o', :primary_site => 'oy' do
      env 'oy' do
        instantiate_stack 'kibana_stack'
      end
    end
  end

  host('oy-kibana-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['server']).to be_nil
    expect(enc['role::kibana']).not_to be_nil
    expect(enc['role::kibana']['elasticsearch_cluster_address']).to eql('oy-elasticsearch-data-vip.oy.net.local')
    expect(enc['role::kibana']['loadbalancer_hosts']).to eql([
      'oy-lb-001.oy.net.local',
      'oy-lb-002.oy.net.local'
    ])
    expect(enc['role::kibana']['prod_vip_fqdn']).to eql('oy-kibana-vip.oy.net.local')
  end

  host('oy-lb-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::loadbalancer']).not_to be_nil
    enc = enc['role::loadbalancer']
    expect(enc['virtual_servers']).not_to be_nil
    expect(enc['virtual_servers']['oy-kibana-vip.oy.net.local']).not_to be_nil
    expect(enc['virtual_servers']['oy-kibana-vip.oy.net.local']['type']).to be_eql('http')
    expect(enc['virtual_servers']['oy-kibana-vip.oy.net.local']['ports']).to be_eql([8000])
    expect(enc['virtual_servers']['oy-kibana-vip.oy.net.local']['realservers']['blue']).to \
      be_eql([
        'oy-kibana-001.oy.net.local',
        'oy-kibana-002.oy.net.local'
      ])
  end
end
