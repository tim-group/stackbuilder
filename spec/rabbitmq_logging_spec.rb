require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'rabbitmq logging cluster' do
  given do
    stack 'per_site_log_collecting' do
      logstash_receiver 'logstash-receiver' do
        depend_on 'rabbitmq-logging', 'e1'
      end

      rabbitmq_logging 'rabbitmq-logging' do
        depend_on 'rabbitmq-elasticsearch', 'e2'
      end
    end

    stack 'centralised_logging_cluster' do
      rabbitmq_logging 'rabbitmq-elasticsearch'
    end

    env 'e1', :primary_site => 'space' do
      instantiate_stack 'per_site_log_collecting'
    end

    env 'e2', :primary_site => 'earth' do
      instantiate_stack 'centralised_logging_cluster'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'e1-rabbitmq-logging-001.mgmt.space.net.local',
      'e1-rabbitmq-logging-002.mgmt.space.net.local',
      'e1-logstash-receiver-001.mgmt.space.net.local',
      'e1-logstash-receiver-002.mgmt.space.net.local',
      'e2-rabbitmq-elasticsearch-001.mgmt.earth.net.local',
      'e2-rabbitmq-elasticsearch-002.mgmt.earth.net.local'
    ])
  end

  host('e1-logstash-receiver-001.mgmt.space.net.local') do |host|
    expect(host.to_enc).to include('role::logstash_receiver')
    role_enc = host.to_enc['role::logstash_receiver']
    expect(role_enc['rabbitmq_logging_username']).to eql('logstash_receiver')
    expect(role_enc['rabbitmq_logging_password_key']).to eql('e1/logstash_receiver/messaging_password')
    expect(role_enc['rabbitmq_logging_exchange']).to eql('logging')

    expect(role_enc['rabbitmq_logging_hosts']).to eql(['e1-rabbitmq-logging-001.space.net.local',
                                                       'e1-rabbitmq-logging-002.space.net.local'])
  end

  host('e1-rabbitmq-logging-001.mgmt.space.net.local') do |host|
    expect(host.to_enc).to include('role::rabbitmq_logging')
    role_enc = host.to_enc['role::rabbitmq_logging']
    pp role_enc

    expect(role_enc['cluster_nodes']).to eql(['e1-rabbitmq-logging-001', 'e1-rabbitmq-logging-002'])
    expect(role_enc['dependant_instances']).to eql(['e1-logstash-receiver-001.space.net.local',
                                                    'e1-logstash-receiver-002.space.net.local',
                                                    'e1-rabbitmq-logging-002.space.net.local'])
    expect(role_enc['dependant_users']).to eql('logstash_receiver' => {
                                                 'password_hiera_key' => 'e1/logstash_receiver/messaging_password',
                                                 'tags' => []
                                               },
                                               'shovel' => {
                                                 'password_hiera_key' => 'e1/shovel/messaging_password',
                                                 'tags' => []
                                               })
    expect(role_enc['shovel_destinations']).to eql(['e2-rabbitmq-elasticsearch-001.earth.net.local',
                                                    'e2-rabbitmq-elasticsearch-002.earth.net.local'])
  end

  host('e2-rabbitmq-elasticsearch-001.mgmt.earth.net.local') do |host|
    expect(host.to_enc).to include('role::rabbitmq_logging')
    role_enc = host.to_enc['role::rabbitmq_logging']

    expect(role_enc['cluster_nodes']).to eql(['e2-rabbitmq-elasticsearch-001', 'e2-rabbitmq-elasticsearch-002'])
    expect(role_enc['dependant_instances']).to eql(['e1-rabbitmq-logging-001.space.net.local',
                                                    'e1-rabbitmq-logging-002.space.net.local',
                                                    'e2-rabbitmq-elasticsearch-002.earth.net.local'])
    expect(role_enc['dependant_users']).to eql('shovel' => {
                                                 'password_hiera_key' => 'e1/shovel/messaging_password',
                                                 'tags' => []
                                               })
  end
end

describe_stack 'rabbitmq logging exchange is configurable' do
  given do
    stack 'logstash_receiver' do
      logstash_receiver 'logstash-receiver' do
        self.exchange = 'my-logging-exchange'
      end
    end

    env 'e1', :primary_site => 'space' do
      instantiate_stack 'logstash_receiver'
    end
  end

  host('e1-logstash-receiver-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::logstash_receiver']['rabbitmq_logging_exchange']).to eql('my-logging-exchange')
  end
end

describe_stack 'rabbitmq logging can have arbitrary users added to it' do
  given do
    stack 'rabbitmq_logging' do
      rabbitmq_logging 'user-added' do
        add_rabbitmq_user(
          'some-new-user',
          'e2/some-new-user/messaging_password',
          'e2-somenewusernode-001.space.net.local')
      end
    end

    env 'e1', :primary_site => 'space' do
      instantiate_stack 'rabbitmq_logging'
    end
  end

  host('e1-user-added-001.mgmt.space.net.local') do |host|
    role_enc = host.to_enc['role::rabbitmq_logging']
    expect(role_enc['dependant_users']).to eql('some-new-user' => {
                                                 'tags' => [],
                                                 'password_hiera_key' => 'e2/some-new-user/messaging_password'
                                               })
    expect(role_enc['dependant_instances']).to eql(['e1-user-added-002.space.net.local',
                                                    'e2-somenewusernode-001.space.net.local'])
  end
end
