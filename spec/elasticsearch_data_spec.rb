require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'elasticsearch data server and associated load balancer enc is correct' do
  given do
    stack 'a_stack' do
      elasticsearch_data 'elasticsearch-data' do
        depend_on 'elasticsearch-master'
      end
      elasticsearch_master 'elasticsearch-master'
      kibana do
        depend_on 'elasticsearch-data'
      end
      logstash_indexer 'logstash-indexer' do
        depend_on 'elasticsearch-data'
      end
      loadbalancer_service
    end

    env 'o', :primary_site => 'oy' do
      env 'oy' do
        instantiate_stack 'a_stack'
      end
    end
  end

  host('oy-elasticsearch-data-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::elasticsearch_data']).not_to be_nil
    role_enc = enc['role::elasticsearch_data']
    expect(role_enc['elasticsearch_master_hosts']).to \
      eql([
        'oy-elasticsearch-master-001.oy.net.local',
        'oy-elasticsearch-master-002.oy.net.local',
        'oy-elasticsearch-master-003.oy.net.local'
      ])
    expect(role_enc['kibana_hosts']).to \
      eql([
        'oy-kibana-001.oy.net.local',
        'oy-kibana-002.oy.net.local'
      ])
    expect(role_enc['loadbalancer_hosts']).to \
      eql([
        'oy-lb-001.oy.net.local',
        'oy-lb-002.oy.net.local'
      ])
    expect(role_enc['logstash_indexer_hosts']).to \
      eql([
        'oy-logstash-indexer-001.oy.net.local',
        'oy-logstash-indexer-002.oy.net.local'
      ])
    expect(role_enc['prod_vip_fqdn']).to eql('oy-elasticsearch-data-vip.oy.net.local')
  end

  host('oy-lb-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::loadbalancer']).not_to be_nil
    enc = enc['role::loadbalancer']
    expect(enc['virtual_servers']).not_to be_nil
    expect(enc['virtual_servers']['oy-elasticsearch-data-vip.oy.net.local']).not_to be_nil
    expect(enc['virtual_servers']['oy-elasticsearch-data-vip.oy.net.local']['type']).to be_eql('elasticsearch_data')
    expect(enc['virtual_servers']['oy-elasticsearch-data-vip.oy.net.local']['ports']).to be_eql([9200])
    expect(enc['virtual_servers']['oy-elasticsearch-data-vip.oy.net.local']['realservers']['blue']).to \
      be_eql(['oy-elasticsearch-data-001.oy.net.local', 'oy-elasticsearch-data-002.oy.net.local'])
    expect(enc['virtual_servers']['oy-elasticsearch-data-vip.oy.net.local']['healthchecks']).to be_eql([
      { "healthcheck" => "TCP_CHECK", "connect_timeout" => "5" }
    ])
  end
end
