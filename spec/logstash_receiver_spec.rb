require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'logstash receiver' do
  given do
    stack "logstash_receiver" do
      logstash_cluster "logstash" do
        self.role = :receiver

        depend_on 'elasticmq'
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

    env "e1", :primary_site => "space", :secondary_site => "earth"  do
      instantiate_stack "logstash_receiver"
      instantiate_stack "elastic_mq"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'e1-logstash-receiver-001.mgmt.space.net.local',
      'e1-elasticmq-001.mgmt.space.net.local',
      'e1-elasticmq-002.mgmt.space.net.local'
    ])
  end

  host("e1-logstash-receiver-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::logstash::receiver']
    expect(enc['version']).to eql('2.2.0')
    expect(enc['rabbitmq_vip']).to eql('e1-elasticmq-vip.space.net.local')
    expect(enc['elastic_vip']).to eql(nil)
  end
end
