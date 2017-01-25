require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'nat servers should have all 3 networks' do
  given do
    stack 'fabric' do
      nat_service
      proxy_service 'proxy' do
        enable_nat
      end
      app_service 'app' do
        enable_nat
      end
    end

    env "oy", :primary_site => "oy" do
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

  host("oy-nat-001.mgmt.oy.net.local") do |host|
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

describe_stack 'nat servers cannot suppot enable_secondary_site' do
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
  host("production-nat-001.mgmt.pg.net.local") do |nat|
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
    stack "frontexample" do
      nat_service
      proxy_service 'withnat' do
        enable_nat
      end
      sftp_service 'sftp' do
        enable_nat
      end
      app_service 'withoutnat' do
      end
    end

    stack "example2" do
      nat_service
      app_service 'blahnat' do
        enable_nat
        self.ports = [8008]
      end
    end

    stack "exampledefaultport" do
      nat_service
      app_service 'defaultport' do
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
    stack "frontexample" do
      nat_service
      proxy_service 'withnat' do
        enable_nat_out
      end
      sftp_service 'sftp' do
        enable_nat_out
      end
      app_service 'withoutnat' do
      end
    end

    stack "example2" do
      nat_service
      app_service 'blahnat' do
        enable_nat_out
        self.ports = [8008]
      end
    end

    stack "exampledefaultport" do
      nat_service
      app_service 'defaultport' do
        enable_nat_out
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

describe_stack 'can depend_on nat' do
  given do
    stack 'depend_on_example' do
      nat_service

      standard_service 'standardwith-dnat' do
        extend(Stacks::Services::CanBeNatted)
        self.instances = 2
        self.ports = [22]

        configure_dnat(:front, :mgmt, true, false)
        depend_on 'nat', environment.name, :nat_to_host
      end

      app_service 'appwith-dnat' do
        self.instances = 2
        self.ports = [8000]

        configure_dnat(:front, :prod, true, true, 8000 => 80)
        depend_on 'nat', environment.name, :nat_to_vip
      end

      standard_service 'standardwith-snat' do
        extend(Stacks::Services::CanBeNatted)
        self.instances = 2
        self.ports = [22]

        configure_snat(:front, :mgmt, true, false)
        depend_on 'nat', environment.name, :nat_to_host
      end

      app_service 'appwith-snat' do
        self.instances = 2
        self.ports = [8000]

        configure_snat(:front, :prod, true, false)
        depend_on 'nat', environment.name, :nat_to_vip
      end

      app_service 'othersitewith-dnat' do
        self.enable_secondary_site = true
        self.ports = [8443]

        configure_dnat(:front, :prod, true, true, 8000 => 80)

        each_machine do |machine|
          case machine.site
          when 'st'
            depend_on 'nat', 'dep', :nat_to_vip
          when 'bs'
            depend_on 'nat', 'other', :nat_to_vip
          end
        end
      end

      app_service 'othersitewith-snat' do
        self.enable_secondary_site = true
        self.ports = [8443]

        configure_snat(:front, :prod, true, true, 8000 => 80)

        each_machine do |machine|
          case machine.site
          when 'st'
            depend_on 'nat', 'dep', :nat_to_vip
          when 'bs'
            depend_on 'nat', 'other', :nat_to_vip
          end
        end
      end
    end

    stack 'other_site_nat' do
      nat_service
    end

    env 'dep', :primary_site => 'st', :secondary_site => 'bs' do
      instantiate_stack 'depend_on_example'
    end

    env 'other', :primary_site => 'bs' do
      instantiate_stack 'other_site_nat'
    end
  end

  host('dep-nat-001.mgmt.st.net.local') do |host|
    enc = host.to_enc
    dnat = enc['role::natserver']['rules']['DNAT']
    snat = enc['role::natserver']['rules']['SNAT']

    first_host_dnat_rules = dnat['dep-standardwith-dnat-001.front.st.net.local 22']
    expect(first_host_dnat_rules['dest_host']).to eql('dep-standardwith-dnat-001.mgmt.st.net.local')
    expect(first_host_dnat_rules['dest_port']).to eql('22')
    expect(first_host_dnat_rules['tcp']).to eql(true)
    expect(first_host_dnat_rules['udp']).to eql(false)

    second_host_dnat_rules = dnat['dep-standardwith-dnat-002.front.st.net.local 22']
    expect(second_host_dnat_rules['dest_host']).to eql('dep-standardwith-dnat-002.mgmt.st.net.local')
    expect(second_host_dnat_rules['dest_port']).to eql('22')
    expect(second_host_dnat_rules['tcp']).to eql(true)
    expect(second_host_dnat_rules['udp']).to eql(false)

    vip_dnat_rules = dnat['dep-appwith-dnat-vip.front.st.net.local 80']
    expect(vip_dnat_rules['dest_host']).to eql('dep-appwith-dnat-vip.st.net.local')
    expect(vip_dnat_rules['dest_port']).to eql('8000')
    expect(vip_dnat_rules['tcp']).to eql(true)
    expect(vip_dnat_rules['udp']).to eql(true)

    standard_host_snat_rules = snat['dep-standardwith-snat-001.mgmt.st.net.local 22']
    expect(standard_host_snat_rules['to_source']).to eql('dep-standardwith-snat-001.front.st.net.local:22')
    expect(standard_host_snat_rules['tcp']).to eql(true)
    expect(standard_host_snat_rules['udp']).to eql(false)

    vip_snat_rules = snat['dep-appwith-snat-vip.st.net.local 8000']
    expect(vip_snat_rules['to_source']).to eql('dep-appwith-snat-vip.front.st.net.local:8000')
    expect(vip_snat_rules['tcp']).to eql(true)
    expect(vip_snat_rules['udp']).to eql(false)

    expect(dnat['dep-othersitewith-dnat-vip.front.bs.net.local 8443']).to be(nil)
    expect(snat['dep-othersitewith-snat-vip.bs.net.local 8443']).to be(nil)
    expect(dnat['dep-othersitewith-dnat-vip.front.st.net.local 8443']['dest_host']).to eql('dep-othersitewith-dnat-vip.st.net.local')
    expect(snat['dep-othersitewith-snat-vip.st.net.local 8443']['to_source']).to eql('dep-othersitewith-snat-vip.front.st.net.local:8443')
  end

  host('other-nat-001.mgmt.bs.net.local') do |host|
    enc = host.to_enc
    dnat = enc['role::natserver']['rules']['DNAT']
    snat = enc['role::natserver']['rules']['SNAT']
    other_site_dnat = dnat['dep-othersitewith-dnat-vip.front.bs.net.local 8443']
    expect(other_site_dnat['dest_host']).to eql('dep-othersitewith-dnat-vip.bs.net.local')
    other_site_snat = snat['dep-othersitewith-snat-vip.bs.net.local 8443']
    expect(other_site_snat['to_source']).to eql('dep-othersitewith-snat-vip.front.bs.net.local:8443')

    expect(dnat['dep-othersitewith-dnat-vip.front.st.net.local 8443']).to be(nil)
    expect(snat['dep-othersitewith-snat-vip.st.net.local 8443']).to be(nil)
  end
end
