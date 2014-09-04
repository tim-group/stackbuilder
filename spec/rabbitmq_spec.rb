require 'stacks/test_framework'

describe_stack 'mongodb' do
  given do
    stack "rabbit" do
      virtual_rabbitmqserver
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "rabbit"
    end
  end

  host("e1-rabbitmq-001.mgmt.space.net.local") do |host|
    host.to_enc['role::rabbitmq_server']['vip_fqdn'].should eql("e1-rabbitmq-vip.space.net.local")
    host.to_enc['role::rabbitmq_server']['cluster_nodes'].should eql(['e1-rabbitmq-001', 'e1-rabbitmq-002'])
    host.to_enc.has_key?('server::default_new_mgmt_net_local').should eql true
  end

end
