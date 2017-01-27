require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'nat servers should have all 3 networks' do
  given do
    stack 'fabric' do
      nat_service
      proxy_service 'proxy' do
        nat_config.dnat_enabled = true
        depend_on 'nat', environment.name
      end
      app_service 'app' do
        nat_config.dnat_enabled = true
        depend_on 'nat', environment.name
      end
    end

    env 'oy', :primary_site => 'oy' do
      instantiate_stack 'fabric'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
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

  host('oy-nat-001.mgmt.oy.net.local') do |host|
    expect(host.to_specs.first[:networks]).to eql([:mgmt, :prod, :front])
    enc_rules = host.to_enc['role::natserver']['rules']
    expect(enc_rules['SNAT']['prod']['to_source']).to eql 'nat-vip.front.oy.net.local'
    expect(enc_rules['DNAT'].size).to eql(3)
    dnat_1 = enc_rules['DNAT']['oy-app-vip.front.oy.net.local 8000']
    expect(dnat_1['dest_host']).to eql('oy-app-vip.oy.net.local')
    expect(dnat_1['dest_port']).to eql('8000')
    expect(dnat_1['tcp']).to eql(true)
    expect(dnat_1['udp']).to eql(false)

    dnat_2 = enc_rules['DNAT']['oy-proxy-vip.front.oy.net.local 80']
    expect(dnat_2['dest_host']).to eql('oy-proxy-vip.oy.net.local')
    expect(dnat_2['dest_port']).to eql('80')
    expect(dnat_2['tcp']).to eql(true)
    expect(dnat_2['udp']).to eql(false)

    dnat_3 = enc_rules['DNAT']['oy-proxy-vip.front.oy.net.local 443']
    expect(dnat_3['dest_host']).to eql('oy-proxy-vip.oy.net.local')
    expect(dnat_3['dest_port']).to eql('443')
    expect(dnat_3['tcp']).to eql(true)
    expect(dnat_3['udp']).to eql(false)
  end
end

describe_stack 'nat servers cannot support enable_secondary_site' do
  given do
    stack 'nat' do
      nat_service do
        @enable_secondary_site = true
      end
    end

    env 'production', :primary_site         => 'pg',
                      :secondary_site       => 'oy',
                      :lb_virtual_router_id => 27 do
      instantiate_stack 'nat'
    end
  end
  host('production-nat-001.mgmt.pg.net.local') do |nat|
    expect { nat.to_enc }.to raise_error('Nat servers do not support secondary_site')
  end
end

describe_stack 'nat servers should provide natting for secondary_site services in my location' do
  given do
    stack 'nat' do
      nat_service
    end

    stack 'example' do
      app_service 'exampleuserapp' do
        self.application = 'example'
        @enable_secondary_site = true
      end
    end

    stack 'example_proxy' do
      proxy_service 'exampleproxy' do
        @enable_secondary_site = true
        vhost('exampleuserapp', 'example-mirror.timgroup.com', 'production')
        nat_config.dnat_enabled = true
        depend_on 'nat', 'shared'
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
  host('shared-nat-001.mgmt.oy.net.local') do |nat|
    dnat = nat.to_enc['role::natserver']['rules']['DNAT']
    expect(dnat.keys).to include(
      'production-exampleproxy-vip.front.oy.net.local 80',
      'production-exampleproxy-vip.front.oy.net.local 443'
    )
    expect(dnat.keys.size).to eql(2)
    expect(dnat['production-exampleproxy-vip.front.oy.net.local 80']['dest_host']).to eql(
      'production-exampleproxy-vip.oy.net.local'
    )
    expect(dnat['production-exampleproxy-vip.front.oy.net.local 443']['dest_host']).to eql(
      'production-exampleproxy-vip.oy.net.local'
    )
  end
end

describe_stack 'configures NAT boxes to NAT incoming public IPs' do
  given do
    stack 'frontexample' do
      nat_service
      proxy_service 'withnat' do
        nat_config.dnat_enabled = true
        depend_on 'nat', environment.name
      end
      sftp_service 'sftp' do
        nat_config.dnat_enabled = true
        depend_on 'nat', environment.name
      end
      app_service 'withoutnat' do
      end
    end

    stack 'example2' do
      nat_service
      app_service 'blahnat' do
        nat_config.dnat_enabled = true
        depend_on 'nat', environment.name
        self.ports = [8008]
      end
    end

    stack 'exampledefaultport' do
      nat_service
      app_service 'defaultport' do
        nat_config.dnat_enabled = true
        depend_on 'nat', environment.name
      end
    end

    env 'eg', :primary_site => 'st', :secondary_site => 'bs' do
      instantiate_stack 'frontexample'
      env 'sub' do
        instantiate_stack 'example2'
        instantiate_stack 'exampledefaultport'
      end
    end
  end
  host('eg-nat-001.mgmt.st.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::natserver']['prod_virtual_router_id']).to eql(106)
    expect(enc['role::natserver']['front_virtual_router_id']).to eql(105)

    snat = enc['role::natserver']['rules']['SNAT']
    snat_1 = snat['prod']
    expect(snat_1['to_source']).to eql('nat-vip.front.st.net.local')

    dnat = enc['role::natserver']['rules']['DNAT']
    expect(dnat.size).to eql(5)
    dnat_1 = dnat['eg-withnat-vip.front.st.net.local 80']
    expect(dnat_1['dest_host']).to eql('eg-withnat-vip.st.net.local')
    expect(dnat_1['dest_port']).to eql('80')
    expect(dnat_1['tcp']).to eql(true)
    expect(dnat_1['udp']).to eql(false)

    dnat_2 = dnat['eg-withnat-vip.front.st.net.local 443']
    expect(dnat_2['dest_host']).to eql('eg-withnat-vip.st.net.local')
    expect(dnat_2['dest_port']).to eql('443')
    expect(dnat_2['tcp']).to eql(true)
    expect(dnat_2['udp']).to eql(false)

    dnat_3 = dnat['eg-sftp-vip.front.st.net.local 21']
    expect(dnat_3['dest_host']).to eql('eg-sftp-vip.st.net.local')
    expect(dnat_3['dest_port']).to eql('21')
    expect(dnat_3['tcp']).to eql(true)
    expect(dnat_3['udp']).to eql(false)

    dnat_4 = dnat['eg-sftp-vip.front.st.net.local 22']
    expect(dnat_4['dest_host']).to eql('eg-sftp-vip.st.net.local')
    expect(dnat_4['dest_port']).to eql('22')
    expect(dnat_4['tcp']).to eql(true)
    expect(dnat_4['udp']).to eql(false)

    dnat_5 = dnat['eg-sftp-vip.front.st.net.local 2222']
    expect(dnat_5['dest_host']).to eql('eg-sftp-vip.st.net.local')
    expect(dnat_5['dest_port']).to eql('2222')
    expect(dnat_5['tcp']).to eql(true)
    expect(dnat_5['udp']).to eql(false)
  end

  host('sub-nat-001.mgmt.st.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::natserver']['prod_virtual_router_id']).to eql(106)
    expect(enc['role::natserver']['front_virtual_router_id']).to eql(105)

    snat = enc['role::natserver']['rules']['SNAT']
    expect(snat['prod']['to_source']).to eql('nat-vip.front.st.net.local')

    dnat = enc['role::natserver']['rules']['DNAT']
    expect(dnat.size).to eql(2)
    dnat_1 = dnat['sub-blahnat-vip.front.st.net.local 8008']
    expect(dnat_1['dest_host']).to eql('sub-blahnat-vip.st.net.local')
    expect(dnat_1['dest_port']).to eql('8008')
    expect(dnat_1['tcp']).to eql(true)
    expect(dnat_1['udp']).to eql(false)

    dnat_2 = dnat['sub-defaultport-vip.front.st.net.local 8000']
    expect(dnat_2['dest_host']).to eql('sub-defaultport-vip.st.net.local')
    expect(dnat_2['dest_port']).to eql('8000')
    expect(dnat_2['tcp']).to eql(true)
    expect(dnat_2['udp']).to eql(false)
  end
end

describe_stack 'configures NAT boxes to NAT specific outgoing things to specific public IPs' do
  given do
    stack 'frontexample' do
      nat_service
      proxy_service 'withnat' do
        nat_config.snat_enabled = true
        depend_on 'nat', 'eg'
      end
      sftp_service 'sftp' do
        nat_config.snat_enabled = true
        depend_on 'nat', 'eg'
      end
      app_service 'withoutnat' do
      end
    end

    stack 'example2' do
      nat_service
      app_service 'blahnat' do
        nat_config.snat_enabled = true
        depend_on 'nat', 'sub'
        self.ports = [8008]
      end
    end

    stack 'exampledefaultport' do
      nat_service
      app_service 'defaultport' do
        nat_config.snat_enabled = true
        depend_on 'nat', 'sub'
      end
    end

    env 'eg', :primary_site => 'st', :secondary_site => 'bs' do
      instantiate_stack 'frontexample'
      env 'sub' do
        instantiate_stack 'example2'
        instantiate_stack 'exampledefaultport'
      end
    end
  end
  host('eg-nat-001.mgmt.st.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::natserver']['prod_virtual_router_id']).to eql(106)
    expect(enc['role::natserver']['front_virtual_router_id']).to eql(105)

    snat = enc['role::natserver']['rules']['SNAT']
    snat_1 = snat['prod']
    expect(snat_1['to_source']).to eql('nat-vip.front.st.net.local')
    snat_2 = snat['eg-withnat-vip.st.net.local 443']
    expect(snat_2['to_source']).to eql('eg-withnat-vip.front.st.net.local:443')
    expect(snat_2['udp']).to eql(false)
    expect(snat_2['tcp']).to eql(true)
    snat_3 = snat['eg-withnat-vip.st.net.local 80']
    expect(snat_3['to_source']).to eql('eg-withnat-vip.front.st.net.local:80')
    expect(snat_3['udp']).to eql(false)
    expect(snat_3['tcp']).to eql(true)
    snat_4 = snat['eg-sftp-vip.st.net.local 21']
    expect(snat_4['to_source']).to eql('eg-sftp-vip.front.st.net.local:21')
    expect(snat_4['tcp']).to eql(true)
    expect(snat_4['udp']).to eql(false)
    snat_5 = snat['eg-sftp-vip.st.net.local 22']
    expect(snat_5['to_source']).to eql('eg-sftp-vip.front.st.net.local:22')
    expect(snat_5['tcp']).to eql(true)
    expect(snat_5['udp']).to eql(false)
    snat_6 = snat['eg-sftp-vip.st.net.local 2222']
    expect(snat_6['to_source']).to eql('eg-sftp-vip.front.st.net.local:2222')
    expect(snat_6['tcp']).to eql(true)
    expect(snat_6['udp']).to eql(false)
  end

  host('sub-nat-001.mgmt.st.net.local') do |host|
    enc = host.to_enc
    expect(enc['role::natserver']['prod_virtual_router_id']).to eql(106)
    expect(enc['role::natserver']['front_virtual_router_id']).to eql(105)

    snat = enc['role::natserver']['rules']['SNAT']
    expect(snat['prod']['to_source']).to eql('nat-vip.front.st.net.local')

    snat_1 = snat['sub-blahnat-vip.st.net.local 8008']
    expect(snat_1['to_source']).to eql('sub-blahnat-vip.front.st.net.local:8008')
    expect(snat_1['tcp']).to eql(true)
    expect(snat_1['udp']).to eql(false)

    snat_2 = snat['sub-defaultport-vip.st.net.local 8000']
    expect(snat_2['to_source']).to eql('sub-defaultport-vip.front.st.net.local:8000')
    expect(snat_2['tcp']).to eql(true)
    expect(snat_2['udp']).to eql(false)
  end
end
