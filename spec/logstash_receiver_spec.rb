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
    stack 'logging_central' do
      elasticsearch_data 'elasticsearch-data'
      loadbalancer_service
    end

    stack 'logging_site' do
      rabbitmq_logging 'rabbitmq-logging'
      logstash_receiver 'logstash-receiver' do
        depend_on 'elasticsearch-data', 'pg'
        depend_on 'rabbitmq-logging'
      end
    end

    env 'o', :primary_site => 'oy' do
      env 'oy' do
        instantiate_stack 'logging_site'
      end
    end

    env 'p', :primary_site => 'pg' do
      env 'pg' do
        instantiate_stack 'logging_central'
        instantiate_stack 'logging_site'
      end
    end
  end

  host('oy-logstash-receiver-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::logstash_receiver']).not_to be_nil
    role_enc = enc['role::logstash_receiver']
    expect(role_enc['rabbitmq_logging_username']).to be_eql('logstash_receiver')
    expect(role_enc['rabbitmq_logging_password_key']).to be_eql('oy/logstash_receiver/messaging_password')
    expect(role_enc['rabbitmq_logging_exchange']).to be_eql('logging')
    expect(role_enc['rabbitmq_logging_hosts']).to \
      be_eql([
        'oy-rabbitmq-logging-001.oy.net.local',
        'oy-rabbitmq-logging-002.oy.net.local'
      ])
    expect(role_enc['elasticsearch_cluster_address']).to be_eql('pg-elasticsearch-data-vip.pg.net.local')
  end

  host('pg-logstash-receiver-001.mgmt.pg.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::logstash_receiver']).not_to be_nil
    role_enc = enc['role::logstash_receiver']
    expect(role_enc['rabbitmq_logging_username']).to be_eql('logstash_receiver')
    expect(role_enc['rabbitmq_logging_password_key']).to be_eql('pg/logstash_receiver/messaging_password')
    expect(role_enc['rabbitmq_logging_exchange']).to be_eql('logging')
    expect(role_enc['rabbitmq_logging_hosts']).to \
      be_eql([
        'pg-rabbitmq-logging-001.pg.net.local',
        'pg-rabbitmq-logging-002.pg.net.local'
      ])
    expect(role_enc['elasticsearch_cluster_address']).to be_eql('pg-elasticsearch-data-vip.pg.net.local')
  end
end

describe_stack 'depend_on logstash receiver respects site of the logging node' do
  given do
    stack 'logging_site' do
      logstash_receiver 'logstash-receiver'
    end

    stack 'multisite_appservice' do
      app_service 'multisite' do
        self.enable_secondary_site = true
        self.instances = 1

        depend_on 'logstash-receiver', 'pg'
      end
    end

    env 'oy', :primary_site => 'oy' do
      instantiate_stack 'logging_site'
    end

    env 'pg', :primary_site => 'pg', :secondary_site => 'oy' do
      instantiate_stack 'logging_site'

      env 'production' do
        depend_on 'logstash-receiver', 'pg'
        depend_on 'logstash-receiver', 'oy'
        instantiate_stack 'multisite_appservice'
      end
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'oy-logstash-receiver-001.mgmt.oy.net.local',
      'oy-logstash-receiver-002.mgmt.oy.net.local',
      'pg-logstash-receiver-002.mgmt.pg.net.local',
      'pg-logstash-receiver-001.mgmt.pg.net.local',
      'production-multisite-001.mgmt.pg.net.local',
      'production-multisite-001.mgmt.oy.net.local'
    ])
  end

  host('production-multisite-001.mgmt.pg.net.local') do |host|
    enc = host.to_enc

    expect(enc['profiles::filebeat']).not_to be_nil
    expect(enc['profiles::filebeat']['logstash_receiver_hosts']).to be_eql([
      'pg-logstash-receiver-001.mgmt.pg.net.local',
      'pg-logstash-receiver-002.mgmt.pg.net.local'
    ])
  end

  host('production-multisite-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc

    expect(enc['profiles::filebeat']).not_to be_nil
    expect(enc['profiles::filebeat']['logstash_receiver_hosts']).to be_eql([
      'oy-logstash-receiver-001.mgmt.oy.net.local',
      'oy-logstash-receiver-002.mgmt.oy.net.local'
    ])
  end
end
