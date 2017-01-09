require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'logstash indexer' do
  given do
    stack 'logstash_indexer' do
      logstash_cluster 'logstash' do
        self.role_in_name = true
        self.instances = {
          'space' => {
            :indexer => 1
          }
        }

        depend_on 'elasticmq'
        depend_on 'elasticlogs'
      end
    end

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
      elasticsearch_cluster "elasticlogs" do
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

    env "e1", :primary_site => "space", :secondary_site => "earth"  do
      instantiate_stack "logstash_indexer"
      instantiate_stack "elastic_mq"
      instantiate_stack "elasticsearch"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'e1-logstash-indexer-001.mgmt.space.net.local',
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

  host("e1-logstash-indexer-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::logstash::indexer']
    pp enc
    expect(enc['version']).to eql('2.2.0')
    expect(enc['rabbitmq_vip']).to eql('e1-elasticmq-vip.space.net.local')
    expect(enc['elastic_vip']).to eql('e1-elasticlogs-vip.space.net.local')
  end
end
