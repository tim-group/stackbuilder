require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'elasticsearch data server and associated load balancer enc is correct' do
  given do
    stack 'a_stack' do
      elasticsearch_data 'elasticsearch-data' do
        depend_on 'elasticsearch-master'
        allow_host 'some-random-app.oy.net.local'
        each_machine do |machine|
          machine.add_node_attribute('test', 'blah') if machine.hostname == 'oy-elasticsearch-data-002'
        end
      end
      elasticsearch_master 'elasticsearch-master'
      kibana do
        depend_on 'elasticsearch-data'
      end
      logstash_indexer 'logstash-indexer' do
        depend_on 'elasticsearch-data'
      end
      logstash_receiver 'logstash-receiver' do
        depend_on 'elasticsearch-data'
      end
      loadbalancer_service
      app_service 'myapp' do
        self.groups = ['blue']
        self.application = 'rw-app'
        depend_on 'elasticsearch-data', environment.name
      end
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
    expect(role_enc['allowed_hosts']).to include('oy-myapp-001.oy.net.local')
    expect(role_enc['allowed_hosts']).to include('some-random-app.oy.net.local')
    expect(role_enc['elasticsearch_master_hosts']).to \
      eql([
        'oy-elasticsearch-master-001.oy.net.local',
        'oy-elasticsearch-master-002.oy.net.local',
        'oy-elasticsearch-master-003.oy.net.local'
      ])
    expect(role_enc['other_elasticsearch_data_hosts']).to \
      eql([
        'oy-elasticsearch-data-002.oy.net.local'
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
    expect(role_enc['logstash_receiver_hosts']).to \
      eql([
        'oy-logstash-receiver-001.oy.net.local',
        'oy-logstash-receiver-002.oy.net.local'
      ])
    expect(role_enc['prod_vip_fqdn']).to eql('oy-elasticsearch-data-vip.oy.net.local')
    expect(role_enc['minimum_master_nodes']).to eql(2)
    expect(role_enc['node_attrs']).to eql({})
  end

  host('oy-elasticsearch-data-002.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::elasticsearch_data']).not_to be_nil
    role_enc = enc['role::elasticsearch_data']
    expect(role_enc['elasticsearch_master_hosts']).to \
      eql([
        'oy-elasticsearch-master-001.oy.net.local',
        'oy-elasticsearch-master-002.oy.net.local',
        'oy-elasticsearch-master-003.oy.net.local'
      ])
    expect(role_enc['other_elasticsearch_data_hosts']).to \
      eql([
        'oy-elasticsearch-data-001.oy.net.local'
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
    expect(role_enc['logstash_receiver_hosts']).to \
      eql([
        'oy-logstash-receiver-001.oy.net.local',
        'oy-logstash-receiver-002.oy.net.local'
      ])
    expect(role_enc['prod_vip_fqdn']).to eql('oy-elasticsearch-data-vip.oy.net.local')
    expect(role_enc['minimum_master_nodes']).to eql(2)
    expect(role_enc['node_attrs']).to eql('test' => 'blah')

    expect(host.dependent_nodes.map(&:mgmt_fqdn)).to include('oy-elasticsearch-data-001.mgmt.oy.net.local')
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

  host('oy-myapp-001.mgmt.oy.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['elasticsearch-data.url']).to eql('http://oy-elasticsearch-data-vip.oy.net.local:9200')
  end
end
