require 'stacks/test_framework'

describe_stack 'nameserver' do
  given do
    stack "nat" do
      natserver
    end

    stack "lb" do
      loadbalancer
    end

    stack "nameserver" do
      virtual_bindserver 'ns' do
        enable_nat
        forwarder_zone(['blah.com'])
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "nameserver"
      instantiate_stack "nat"
      instantiate_stack "lb"
    end
  end

  host("e1-ns-001.mgmt.space.net.local") do |host|
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
    host.to_enc['role::bind_server']['role'].should eql('master')
    host.to_enc['role::bind_server']['site'].should eql('space')
    host.to_enc['role::bind_server']['master_fqdn'].should eql('e1-ns-001.space.net.local')
    host.to_enc['role::bind_server']['slaves_fqdn'].should eql(['e1-ns-002.space.net.local'])
    host.to_enc['role::bind_server']['vip_fqdns'].should include('e1-ns-vip.mgmt.space.net.local')
    host.to_enc['role::bind_server']['vip_fqdns'].should include('e1-ns-vip.space.net.local')
    host.to_enc['role::bind_server']['zones'].should eql([
        'mgmt.space.net.local',
        'space.net.local',
        'front.space.net.local',
    ])
    host.to_enc['role::bind_server']['forwarder_zones'].should eql([
      'blah.com'
    ])
    #  'vip_fqdns'    =>  ['e1-ns-vip.mgmt.space.net.local', 'e1-ns-vip.space.net.local'],
  end

  host("e1-ns-002.mgmt.space.net.local") do |host|
    host.to_enc['server::default_new_mgmt_net_local'].should be_nil
    host.to_enc['role::bind_server']['role'].should eql('slave')
    host.to_enc['role::bind_server']['site'].should eql('space')
    host.to_enc['role::bind_server']['master_fqdn'].should eql('e1-ns-001.space.net.local')
    host.to_enc['role::bind_server']['slaves_fqdn'].should eql(['e1-ns-002.space.net.local'])
    host.to_enc['role::bind_server']['vip_fqdns'].should include('e1-ns-vip.mgmt.space.net.local')
    host.to_enc['role::bind_server']['vip_fqdns'].should include('e1-ns-vip.space.net.local')
    host.to_enc['role::bind_server']['zones'].should eql([
        'mgmt.space.net.local',
        'space.net.local',
        'front.space.net.local',
    ])
    host.to_enc['role::bind_server']['forwarder_zones'].should eql([
      'blah.com'
    ])
  end

  host("e1-nat-001.mgmt.space.net.local") do |host|
    host.to_enc['role::natserver']['rules']['DNAT']['e1-ns-vip.front.space.net.local 53']['dest_host'].should eql('e1-ns-vip.space.net.local')
    host.to_enc['role::natserver']['rules']['DNAT']['e1-ns-vip.front.space.net.local 53']['dest_port'].should eql('53')
    host.to_enc['role::natserver']['rules']['DNAT']['e1-ns-vip.front.space.net.local 53']['tcp'].should eql('true')
    host.to_enc['role::natserver']['rules']['DNAT']['e1-ns-vip.front.space.net.local 53']['udp'].should eql('true')
  end

  host("e1-lb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::loadbalancer']['virtual_servers']['e1-ns-vip.space.net.local']['healthchecks'].should include(
      {"MISC_CHECK"=>"misc_path '/usr/bin/host -4 -W 3 -t A -s apt.mgmt.space.net.local"},
      {"MISC_CHECK"=>"misc_path '/usr/bin/host -4 -W 3 -t A -s gw-vip.space.net.local"},
      {"MISC_CHECK"=>"misc_path '/usr/bin/host -4 -W 3 -t A -s gw-vip.front.space.net.local"}
    )
  end
end
