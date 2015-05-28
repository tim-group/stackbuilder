require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'mongodb' do
  given do
    stack "rabbit" do
      virtual_rabbitmqserver 'rabbitmq'
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

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    host.to_enc['role::rabbitmq_server']['vip_fqdn'].should eql("e1-rabbitmq-vip.space.net.local")
    host.to_enc['role::rabbitmq_server']['cluster_nodes'].should eql(['e1-rabbitmq-001', 'e1-rabbitmq-002'])
    host.to_enc['role::rabbitmq_server']['dependant_instances'].
      should eql(['e1-exampleapp-001.space.net.local', 'e1-exampleapp-002.space.net.local'])
    host.to_enc['role::rabbitmq_server']['dependencies'].should eql({})
    host.to_enc.key?('server::default_new_mgmt_net_local').should eql true
  end
end
