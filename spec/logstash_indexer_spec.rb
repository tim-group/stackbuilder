require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'logstash indexer server enc is correct' do
  given do
    stack 'a_stack' do
      elasticsearch_data 'elasticsearch-data' do
        xpack_monitoring_destination
      end
      elasticsearch_data 'elasticsearch-data2'
      rabbitmq_logging 'rabbitmq-elasticsearch'
      logstash_indexer 'logstash-indexer' do
        depend_on 'elasticsearch-data'
        depend_on 'elasticsearch-data2'
        depend_on 'rabbitmq-elasticsearch'
      end
      loadbalancer_service
    end

    env 'o', :primary_site => 'oy' do
      env 'oy' do
        instantiate_stack 'a_stack'
      end
    end
  end

  host('oy-logstash-indexer-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::logstash_indexer']).not_to be_nil
    expect(enc['role::logstash_indexer']['rabbitmq_central_username']).to be_eql('logstash_indexer')
    expect(enc['role::logstash_indexer']['rabbitmq_central_password_key']).to be_eql('oy/logstash_indexer/messaging_password')
    expect(enc['role::logstash_indexer']['rabbitmq_central_exchange']).to be_eql('logging')
    expect(enc['role::logstash_indexer']['rabbitmq_central_hosts']).to \
      be_eql([
        'oy-rabbitmq-elasticsearch-001.oy.net.local',
        'oy-rabbitmq-elasticsearch-002.oy.net.local'
      ])
    expect(enc['role::logstash_indexer']['elasticsearch_data_hosts']).to be_nil
    expect(enc['role::logstash_indexer']['xpack_monitoring_elasticsearch_url']).to be_eql('oy-elasticsearch-data-vip.oy.net.local')
    expect(enc['role::logstash_indexer']['elasticsearch_clusters']).to \
      be_eql('oy-elasticsearch-data-vip.oy.net.local' => [
        'oy-elasticsearch-data-001.oy.net.local',
        'oy-elasticsearch-data-002.oy.net.local'
      ],
             'oy-elasticsearch-data2-vip.oy.net.local' => [
               'oy-elasticsearch-data2-001.oy.net.local',
               'oy-elasticsearch-data2-002.oy.net.local'
             ])
  end
end
