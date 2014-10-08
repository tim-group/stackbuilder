require 'stacks/test_framework'

describe_stack 'nameserver' do
  given do
    stack "nameserver" do
      virtual_nameserver 'ns'
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "nameserver"
    end
  end

  host("e1-ns-001.mgmt.space.net.local") do |host|
    host.to_enc['role::ns_servers'].should be_nil
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
  end
end
