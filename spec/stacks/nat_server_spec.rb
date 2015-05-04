describe_stack 'nat servers should have all 3 networks' do
  given do
    stack 'fabric' do
      natserver
      virtual_proxyserver 'proxy' do
        enable_nat
      end
      virtual_appserver 'app' do
        enable_nat
      end
    end

    env "oy", :primary_site => "oy" do
      instantiate_stack 'fabric'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    stack.should have_hosts(
      [
        'oy-nat-001.mgmt.oy.net.local',
        'oy-nat-002.mgmt.oy.net.local',
        'oy-proxy-001.mgmt.oy.net.local',
        'oy-proxy-002.mgmt.oy.net.local',
        'oy-app-001.mgmt.oy.net.local',
        'oy-app-002.mgmt.oy.net.local'
      ]
    )
  end

  host("oy-nat-001.mgmt.oy.net.local") do |host|
    host.to_specs.first[:networks].should eql([:mgmt, :prod, :front])
    enc_rules = host.to_enc['role::natserver']['rules']
    enc_rules['SNAT']['prod']['to_source'].should eql 'nat-vip.front.oy.net.local'
    enc_rules['DNAT'].size.should eql(3)
    dnat_1 = enc_rules['DNAT']['oy-app-vip.front.oy.net.local 8000']
    dnat_1['dest_host'].should eql('oy-app-vip.oy.net.local')
    dnat_1['dest_port'].should eql('8000')
    dnat_1['tcp'].should eql('true')
    dnat_1['udp'].should eql('false')

    dnat_2 = enc_rules['DNAT']['oy-proxy-vip.front.oy.net.local 80']
    dnat_2['dest_host'].should eql('oy-proxy-vip.oy.net.local')
    dnat_2['dest_port'].should eql('80')
    dnat_2['tcp'].should eql('true')
    dnat_2['udp'].should eql('false')

    dnat_3 = enc_rules['DNAT']['oy-proxy-vip.front.oy.net.local 443']
    dnat_3['dest_host'].should eql('oy-proxy-vip.oy.net.local')
    dnat_3['dest_port'].should eql('443')
    dnat_3['tcp'].should eql('true')
    dnat_3['udp'].should eql('false')
  end
end
