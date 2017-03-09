require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

# Old logstash receiver code
describe_stack 'logstash receiver' do
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

    env 'e1', :primary_site => 'space', :secondary_site => 'earth'  do
      instantiate_stack 'elastic_mq'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'e1-elasticmq-001.mgmt.space.net.local',
      'e1-elasticmq-002.mgmt.space.net.local'
    ])
  end
end

# New logstash receiver code
describe_stack 'logstash indexer server enc is correct' do
  given do
    stack 'a_stack' do
      elasticsearch_data 'elasticsearch-data'
      rabbitmq_logging 'rabbitmq-logging'
      logstash_receiver 'logstash-receiver' do
        depend_on 'elasticsearch-data'
        depend_on 'rabbitmq-logging'
      end
      loadbalancer_service
    end

    env 'o', :primary_site => 'oy' do
      env 'oy' do
        instantiate_stack 'a_stack'
      end
    end
  end

  host('oy-logstash-receiver-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    pp enc

    expect(enc['role::logstash_receiver']).not_to be_nil
    expect(enc['role::logstash_receiver']['rabbitmq_logging_username']).to be_eql('logstash_receiver')
    expect(enc['role::logstash_receiver']['rabbitmq_logging_password_key']).to be_eql('oy/logstash_receiver/messaging_password')
    expect(enc['role::logstash_receiver']['rabbitmq_logging_exchange']).to be_eql('logging')
    expect(enc['role::logstash_receiver']['rabbitmq_logging_hosts']).to \
      be_eql([
        'oy-rabbitmq-logging-001.oy.net.local',
        'oy-rabbitmq-logging-002.oy.net.local'
      ])
    expect(enc['role::logstash_receiver']['elasticsearch_cluster_address']).to be_eql('oy-elasticsearch-data-vip.oy.net.local')
  end
end
