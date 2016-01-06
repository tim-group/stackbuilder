
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'test enc of vpn servers' do
  given do
    stack "nat" do
      natserver
    end

    stack "lb" do
      loadbalancer
    end

    stack 'vpn_stack' do
      vpn_service 'vpn' do
        enable_nat
      end
    end

    env "oymigration", :primary_site => "oy" do
      instantiate_stack "lb"
      instantiate_stack "vpn_stack"
      instantiate_stack 'nat'
    end
  end

  # OY Master
  host("oymigration-vpn-001.mgmt.oy.net.local") do |host|
    enc = host.to_enc
    expect(enc['server::default_new_mgmt_net_local']).to eql({})
    #   expect(enc['role::vpn']).to eql({})
  end

  host('oymigration-lb-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    expect(enc).to eql("role::loadbalancer" => {
                         "virtual_router_id" => 1,
                         "virtual_servers" => {}
                       })
  end

  host('oymigration-nat-001.mgmt.oy.net.local') do |host|
    enc = host.to_enc
    nat_role_dnat = enc['role::natserver']['rules']['DNAT']
    [500, 4500].each do |port|
      expect(nat_role_dnat["oymigration-vpn-vip.front.oy.net.local #{port}"]).to(
        eql(
          "dest_host" => "oymigration-vpn-vip.oy.net.local",
          "dest_port" => "#{port}",
          "tcp" => false,
          "udp" => true
        )
      )
    end
  end
end
