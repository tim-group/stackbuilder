require 'stacks/test_framework'

describe_stack 'nameserver' do
  given do
    stack "nameserver" do
      virtual_bindserver 'ns'
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "nameserver"
    end
  end

  host("e1-ns-001.mgmt.space.net.local") do |host|
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
    host.to_enc['role::bind_server'].should eql({
      'role'         => :master,
      'slaves_fqdn'  => ['e1-ns-002.space.net.local'],
      'zones'        => [
        'mgmt.space.net.local',
        'space.net.local',
        'front.space.net.local'],
    })
  end

  host("e1-ns-002.mgmt.space.net.local") do |host|
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
    host.to_enc['role::bind_server'].should eql({
      'role'         => :slave,
      'master_fqdn'  => ['e1-ns-001.space.net.local'],
      'zones'        => [
        'mgmt.space.net.local',
        'space.net.local',
        'front.space.net.local'],
   })
  end
end
