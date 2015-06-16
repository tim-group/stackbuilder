require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

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
    dnat_1['tcp'].should eql(true)
    dnat_1['udp'].should eql(false)

    dnat_2 = enc_rules['DNAT']['oy-proxy-vip.front.oy.net.local 80']
    dnat_2['dest_host'].should eql('oy-proxy-vip.oy.net.local')
    dnat_2['dest_port'].should eql('80')
    dnat_2['tcp'].should eql(true)
    dnat_2['udp'].should eql(false)

    dnat_3 = enc_rules['DNAT']['oy-proxy-vip.front.oy.net.local 443']
    dnat_3['dest_host'].should eql('oy-proxy-vip.oy.net.local')
    dnat_3['dest_port'].should eql('443')
    dnat_3['tcp'].should eql(true)
    dnat_3['udp'].should eql(false)
  end
end

describe_stack 'nat servers cannot suppot enable_secondary_site' do
  given do
    stack 'nat' do
      natserver do
        @enable_secondary_site = true
      end
    end

    env 'production', :primary_site         => 'pg',
                      :secondary_site       => 'oy',
                      :lb_virtual_router_id => 27 do
      instantiate_stack 'nat'
    end
  end
  host("production-nat-001.mgmt.pg.net.local") do |nat|
    expect { nat.to_enc }.to raise_error('Nat servers do not support secondary_site')
  end
end

describe_stack 'nat servers should provide natting for secondary_site services in my location' do
  given do
    stack 'nat' do
      natserver
    end

    stack 'example' do
      virtual_appserver 'exampleuserapp' do
        self.application = 'example'
        @enable_secondary_site = true
      end
    end

    stack 'example_proxy' do
      virtual_proxyserver 'exampleproxy' do
        @enable_secondary_site = true
        vhost('exampleuserapp', 'example-mirror.timgroup.com', 'production')
        enable_nat
      end
    end

    env 'shared', :primary_site         => 'oy',
                  :secondary_site       => 'pg',
                  :lb_virtual_router_id => 27 do
      instantiate_stack 'nat'
    end

    env 'production', :primary_site         => 'pg',
                      :secondary_site       => 'oy',
                      :lb_virtual_router_id => 27 do
      instantiate_stack 'example_proxy'
      instantiate_stack 'example'
    end
  end
  host("shared-nat-001.mgmt.oy.net.local") do |nat|
    dnat = nat.to_enc['role::natserver']['rules']['DNAT']
    dnat.keys.should include(
      'production-exampleproxy-vip.front.oy.net.local 80',
      'production-exampleproxy-vip.front.oy.net.local 443'
    )
    dnat.keys.size.should eql(2)
    dnat['production-exampleproxy-vip.front.oy.net.local 80']['dest_host'].should eql(
      'production-exampleproxy-vip.oy.net.local'
    )
    dnat['production-exampleproxy-vip.front.oy.net.local 443']['dest_host'].should eql(
      'production-exampleproxy-vip.oy.net.local'
    )
  end
end
describe_stack 'configures NAT boxes to NAT incoming public IPs' do
  given do
    stack "frontexample" do
      natserver
      virtual_proxyserver 'withnat' do
        enable_nat
      end
      virtual_sftpserver 'sftp' do
        enable_nat
      end
      virtual_appserver 'withoutnat' do
      end
    end

    stack "example2" do
      natserver
      virtual_appserver 'blahnat' do
        enable_nat
        self.ports = [8008]
      end
    end

    stack "exampledefaultport" do
      natserver
      virtual_appserver 'defaultport' do
        enable_nat
      end
    end

    env "eg", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "frontexample"
      env "sub" do
        instantiate_stack "example2"
        instantiate_stack "exampledefaultport"
      end
    end
  end
  host('eg-nat-001.mgmt.st.net.local') do |host|
    enc = host.to_enc
    enc['role::natserver']['prod_virtual_router_id'].should eql(106)
    enc['role::natserver']['front_virtual_router_id'].should eql(105)

    snat = enc['role::natserver']['rules']['SNAT']
    snat['prod']['to_source'].should eql('nat-vip.front.st.net.local')

    dnat = enc['role::natserver']['rules']['DNAT']
    dnat.size.should eql(5)
    dnat_1 = dnat['eg-withnat-vip.front.st.net.local 80']
    dnat_1['dest_host'].should eql('eg-withnat-vip.st.net.local')
    dnat_1['dest_port'].should eql('80')
    dnat_1['tcp'].should eql(true)
    dnat_1['udp'].should eql(false)

    dnat_2 = dnat['eg-withnat-vip.front.st.net.local 443']
    dnat_2['dest_host'].should eql('eg-withnat-vip.st.net.local')
    dnat_2['dest_port'].should eql('443')
    dnat_2['tcp'].should eql(true)
    dnat_2['udp'].should eql(false)

    dnat_3 = dnat['eg-sftp-vip.front.st.net.local 21']
    dnat_3['dest_host'].should eql('eg-sftp-vip.st.net.local')
    dnat_3['dest_port'].should eql('21')
    dnat_3['tcp'].should eql(true)
    dnat_3['udp'].should eql(false)

    dnat_4 = dnat['eg-sftp-vip.front.st.net.local 22']
    dnat_4['dest_host'].should eql('eg-sftp-vip.st.net.local')
    dnat_4['dest_port'].should eql('22')
    dnat_4['tcp'].should eql(true)
    dnat_4['udp'].should eql(false)

    dnat_5 = dnat['eg-sftp-vip.front.st.net.local 2222']
    dnat_5['dest_host'].should eql('eg-sftp-vip.st.net.local')
    dnat_5['dest_port'].should eql('2222')
    dnat_5['tcp'].should eql(true)
    dnat_5['udp'].should eql(false)
  end

  host('sub-nat-001.mgmt.st.net.local') do |host|
    enc = host.to_enc
    enc['role::natserver']['prod_virtual_router_id'].should eql(106)
    enc['role::natserver']['front_virtual_router_id'].should eql(105)

    snat = enc['role::natserver']['rules']['SNAT']
    snat['prod']['to_source'].should eql('nat-vip.front.st.net.local')

    dnat = enc['role::natserver']['rules']['DNAT']
    dnat.size.should eql(2)
    dnat_1 = dnat['sub-blahnat-vip.front.st.net.local 8008']
    dnat_1['dest_host'].should eql('sub-blahnat-vip.st.net.local')
    dnat_1['dest_port'].should eql('8008')
    dnat_1['tcp'].should eql(true)
    dnat_1['udp'].should eql(false)

    dnat_2 = dnat['sub-defaultport-vip.front.st.net.local 8000']
    dnat_2['dest_host'].should eql('sub-defaultport-vip.st.net.local')
    dnat_2['dest_port'].should eql('8000')
    dnat_2['tcp'].should eql(true)
    dnat_2['udp'].should eql(false)
  end
end
