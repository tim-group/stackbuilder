require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

# Old logstash indexer code
describe_stack 'logstash indexer' do
  given do
    stack 'elastic_mq' do
      rabbitmq_cluster 'elasticmq' do
        # FIXME: - this should be default in rabbitmq_cluster
        self.ports = [5672]

        storage = {
          '/var/lib/rabbitmq' => { :type => 'data', :size => '100G' }
        }
        each_machine do |machine|
          machine.modify_storage(storage)
          machine.ram = '4194304'
        end
      end
    end

    stack 'elasticsearch' do
      elasticsearch_cluster 'elasticlogs' do
        self.instances = { 'space' => { :master => 3, :data => 4 } }

        each_machine do |machine|
          machine.modify_storage(
            '/mnt/data' => {
              :persistence_options => { :on_storage_not_found => 'create_new' }
            }
          )
        end
        allow_host '0.0.0.0/0'
      end
    end

    env 'e1', :primary_site => 'space', :secondary_site => 'earth'  do
      instantiate_stack 'elastic_mq'
      instantiate_stack 'elasticsearch'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'e1-elasticmq-001.mgmt.space.net.local',
      'e1-elasticmq-002.mgmt.space.net.local',
      'e1-elasticlogs-data-001.mgmt.space.net.local',
      'e1-elasticlogs-data-002.mgmt.space.net.local',
      'e1-elasticlogs-data-003.mgmt.space.net.local',
      'e1-elasticlogs-data-004.mgmt.space.net.local',
      'e1-elasticlogs-master-001.mgmt.space.net.local',
      'e1-elasticlogs-master-002.mgmt.space.net.local',
      'e1-elasticlogs-master-003.mgmt.space.net.local'
    ])
  end
end

# New logstash indexer code
describe_stack 'logstash indexer server enc is correct' do
  given do
    stack 'a_stack' do
      elasticsearch_data 'elasticsearch-data'
      rabbitmq_logging 'rabbitmq-elasticsearch'
      logstash_indexer 'logstash-indexer' do
        depend_on 'elasticsearch-data'
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
    expect(enc['role::logstash_indexer']['elasticsearch_data_hosts']).to \
      be_eql([
        'oy-elasticsearch-data-001.oy.net.local',
        'oy-elasticsearch-data-002.oy.net.local'
      ])
  end
end
