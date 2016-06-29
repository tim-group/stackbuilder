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
    expect(host.to_enc['role::rabbitmq_server']['dependant_instances']).to include(
      'e1-rabbitmq-002.space.net.local')
    expect(host.to_enc['role::rabbitmq_server']['dependant_instances']).not_to include(
      'e1-rabbitmq-001.space.net.local')
    expect(host.to_enc['role::rabbitmq_server']['dependencies']).to be_empty
    expect(host.to_enc['role::rabbitmq_server']['users']).to be_nil
    expect(host.to_enc.key?('server::default_new_mgmt_net_local')).to eql true
  end
end

describe_stack 'app without requirement' do
  given do
    stack "rabbit" do
      rabbitmq_cluster 'rabbitmq'
    end

    stack "example" do
      app_service 'exampleapp' do
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
      app_service 'exampleapp' do
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
    expect(dependencies['magic.messaging.password_hiera_key']).to eql('enc/e1/example/messaging_password')
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::rabbitmq_server']['dependant_instances']).to include(
      'e1-exampleapp-001.space.net.local',
      'e1-exampleapp-002.space.net.local',
      'e1-rabbitmq-002.space.net.local')
    expect(host.to_enc['role::rabbitmq_server']['dependant_instances']).not_to include(
      'e1-rabbitmq-001.space.net.local')
  end
end

describe_stack 'rabbitmq users are created from dependencies' do
  given do
    stack 'test' do
      rabbitmq_cluster 'rabbitmq'
      app_service 'exampleapp' do
        self.application = 'example'
        depend_on 'rabbitmq', 'e1', :wizard
        depend_on 'rabbitmq', 'e1', :magic
      end
      app_service 'eggapp' do
        self.application = 'egg'
        depend_on 'rabbitmq', 'e1', :spoon
      end
      external_service "oy-mon-001.oy.net.local" do
        depend_on 'rabbitmq', 'e1', 'external'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack 'test'
    end
  end

  host("e1-exampleapp-001.mgmt.space.net.local") do |host|
    dependencies = host.to_enc['role::http_app']['dependencies']
    expect(dependencies['magic.messaging.username']).to eql('example')
    expect(dependencies['magic.messaging.password_hiera_key']).to eql('enc/e1/example/messaging_password')
    expect(dependencies['wizard.messaging.username']).to eql('example')
    expect(dependencies['wizard.messaging.password_hiera_key']).to eql('enc/e1/example/messaging_password')
  end

  host("e1-eggapp-001.mgmt.space.net.local") do |host|
    dependencies = host.to_enc['role::http_app']['dependencies']
    expect(dependencies['spoon.messaging.username']).to eql('egg')
    expect(dependencies['spoon.messaging.password_hiera_key']).to eql('enc/e1/egg/messaging_password')
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::rabbitmq_server']['dependant_users']).to include 'example', 'egg'
    expect(host.to_enc['role::rabbitmq_server']['dependant_users']['example']).to eql(
      'password_hiera_key' => 'enc/e1/example/messaging_password',
      'tags'               => []
    )
    expect(host.to_enc['role::rabbitmq_server']['dependant_users']['egg']).to eql(
      'password_hiera_key' => 'enc/e1/egg/messaging_password',
      'tags'               => []
    )
  end
end

describe_stack 'rabbitmq users are not created unless services have application' do
  given do
    stack 'test' do
      rabbitmq_cluster 'rabbitmq'
      external_service "oy-mon-001.oy.net.local" do
        depend_on 'rabbitmq', 'e1', 'external'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack 'test'
    end
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::rabbitmq_server']['dependant_users']).to be_empty
  end
end
