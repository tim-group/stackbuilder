require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

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
