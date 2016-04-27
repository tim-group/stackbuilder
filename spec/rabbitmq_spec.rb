require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'basic rabbitmq cluster' do
  given do
    stack "rabbit" do
      rabbitmq_cluster 'rabbitmq'
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "rabbit"
    end
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::rabbitmq_server']['vip_fqdn']).to eql("e1-rabbitmq-vip.space.net.local")
    expect(host.to_enc['role::rabbitmq_server']['cluster_nodes']).to eql(['e1-rabbitmq-001', 'e1-rabbitmq-002'])
    expect(host.to_enc['role::rabbitmq_server']['dependant_instances']).to be_nil
    expect(host.to_enc['role::rabbitmq_server']['dependencies']).to be_nil
    expect(host.to_enc.key?('server::default_new_mgmt_net_local')).to eql true
  end
end

describe_stack 'app without requirement' do
  given do
    stack "rabbit" do
      rabbitmq_cluster 'rabbitmq'
    end

    stack "example" do
      virtual_appserver 'exampleapp' do
        depend_on "rabbitmq"
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "rabbit"
      instantiate_stack "example"
    end
  end

  host("e1-exampleapp-001.mgmt.space.net.local") do |host|
    expect { host.to_enc }.to raise_error(RuntimeError)
  end
end

describe_stack 'app with rabbitmq dependency' do
  given do
    stack 'test' do
      rabbitmq_cluster 'rabbitmq'
      virtual_appserver 'exampleapp' do
        self.application = 'example'
        depend_on 'rabbitmq', 'e1', :magic
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack 'test'
    end
  end

  host("e1-exampleapp-001.mgmt.space.net.local") do |host|
    dependencies = host.to_enc['role::http_app']['dependencies']
    expect(dependencies['magic.messaging.enabled']).to eql('true')
    expect(dependencies['magic.messaging.broker_fqdns']).to \
      eql('e1-rabbitmq-001.space.net.local,e1-rabbitmq-002.space.net.local')
    expect(dependencies['magic.messaging.username']).to eql('example')
    expect(dependencies['magic.messaging.password_hiera_key']).to eql('enc/e1/example/messaging_magic_password')
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::rabbitmq_server']['dependant_instances']).to \
      eql(['e1-exampleapp-001.space.net.local', 'e1-exampleapp-002.space.net.local'])
  end
end
