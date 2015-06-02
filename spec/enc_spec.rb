require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'

describe Stacks::DSL do
  before do
    extend Stacks::DSL
  end

  it 'can pass in virtual_router_id for the loadbalancers and nat boxes to the stack instantiation' do
    stack "fabric" do
      loadbalancer
      natserver
    end

    env "parent", :primary_site => "st", :secondary_site => "bs" do
      env "e1", :lb_virtual_router_id => 1,
                :nat_front_virtual_router_id => 40,
                :nat_prod_virtual_router_id => 41,
                :primary_site => "space" do
        instantiate_stack "fabric"
      end

      env "e2", :lb_virtual_router_id => 2,
                :nat_front_virtual_router_id => 42,
                :nat_prod_virtual_router_id => 43 do
        instantiate_stack "fabric"
      end
    end

    find("e1-lb-001.mgmt.space.net.local").virtual_router_id.should eql(1)
    find("e2-lb-001.mgmt.st.net.local").virtual_router_id.should eql(2)
    find("e1-nat-001.mgmt.space.net.local").virtual_router_ids[:front].should eql(40)
    find("e2-nat-001.mgmt.st.net.local").virtual_router_ids[:front].should eql(42)
    find("e1-nat-001.mgmt.space.net.local").virtual_router_ids[:prod].should eql(41)
    find("e2-nat-001.mgmt.st.net.local").virtual_router_ids[:prod].should eql(43)
  end

  it 'can generate a pair of loadbalancers' do
    stack "fabric" do
      loadbalancer
    end
    env "rah", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
    end
    find("rah-lb-001.mgmt.st.net.local").should_not be_nil
    find("rah-lb-002.mgmt.st.net.local").should_not be_nil
  end

  it 'generates load balancer enc data with persistent when enable_persistent is specified' do
    stack "loadbalancer" do
      loadbalancer
    end

    stack "sftp" do
      virtual_sftpserver "sftp" do
        enable_persistence '21'
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "loadbalancer"
      instantiate_stack "sftp"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    enc = loadbalancer.to_enc
    enc['role::loadbalancer']['virtual_servers']['st-sftp-vip.st.net.local']['type'].should eql('sftp')
    enc['role::loadbalancer']['virtual_servers']['st-sftp-vip.st.net.local']['realservers']['blue'].should \
      eql(["st-sftp-001.st.net.local", "st-sftp-002.st.net.local"])
    enc['role::loadbalancer']['virtual_servers']['st-sftp-vip.st.net.local']['persistent_ports'].should eql(['21'])
    enc['role::loadbalancer']['virtual_router_id'].should eql(1)
  end

  it 'generates load balancer enc data with the correct warn_level based on fewest number of servers in a group' do
    stack "fabric" do
      loadbalancer
    end

    stack "twoapp" do
      virtual_appserver "twoapp"
    end

    stack "oneapp" do
      virtual_appserver "oneapp" do
        self.groups = %w(blue green)
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
      instantiate_stack "twoapp"
      instantiate_stack "oneapp"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    loadbalancer.to_enc.should eql(
      "role::loadbalancer" => {
        "virtual_router_id" => 1,
        "virtual_servers" => {
          "st-twoapp-vip.st.net.local" => {
            "healthcheck_timeout" => 10,
            "realservers" => {
              "blue" => ["st-twoapp-001.st.net.local", "st-twoapp-002.st.net.local"]
            },
            "env" => "st",
            "app" => nil,
            "monitor_warn" => 1 },
          "st-oneapp-vip.st.net.local" => {
            "healthcheck_timeout" => 10,
            "realservers" => {
              "green" => ["st-oneapp-002.st.net.local"],
              "blue" => ["st-oneapp-001.st.net.local"]
            },
            "env" => "st",
            "app" => nil,
            "monitor_warn" => 0
          }
        }
      }
    )
  end

  it 'generates load balancer enc data with the a different healthcheck_timeout if specified' do
    stack "fabric" do
      loadbalancer
    end

    stack "twoapp" do
      virtual_appserver "twoapp"
    end

    stack "oneapp" do
      virtual_appserver "oneapp" do
        self.groups = %w(blue green)
        self.healthcheck_timeout = 999
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "fabric"
      instantiate_stack "twoapp"
      instantiate_stack "oneapp"
    end
    loadbalancer = find("st-lb-001.mgmt.st.net.local")
    loadbalancer.to_enc.should eql(
      "role::loadbalancer" => {
        "virtual_router_id" => 1,
        "virtual_servers" => {
          "st-twoapp-vip.st.net.local" => {
            "healthcheck_timeout" => 10,
            "realservers" => {
              "blue" => ["st-twoapp-001.st.net.local", "st-twoapp-002.st.net.local"]
            },
            "env" => "st",
            "app" => nil,
            "monitor_warn" => 1
          },
          "st-oneapp-vip.st.net.local" => {
            "healthcheck_timeout" => 10,
            "realservers" => {
              "green" => ["st-oneapp-002.st.net.local"],
              "blue" => ["st-oneapp-001.st.net.local"]
            },
            "env" => "st",
            "app" => nil,
            "monitor_warn" => 0,
            "healthcheck_timeout" => 999
          }
        }
      }
    )
  end

  it 'round robins the groups foreach instance' do
    stack "blah" do
      virtual_appserver "appx" do
        self.instances = 4
        self.application = "JavaHttpRef"
        self.groups = %w(blue green)
      end
    end
    env "ci", :primary_site => "st" do
      instantiate_stack "blah"
    end

    find("ci-appx-001.mgmt.st.net.local").should be_in_group('blue')
    find("ci-appx-002.mgmt.st.net.local").should be_in_group('green')
    find("ci-appx-003.mgmt.st.net.local").should be_in_group('blue')
    find("ci-appx-004.mgmt.st.net.local").should be_in_group('green')
  end

  it 'generates app server configuration appropriately' do
    stack "blah" do
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
      end
    end

    env "ci", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "blah"
    end

    server = find("ci-appx-001.mgmt.st.net.local")
    server.to_enc.should eql('role::http_app' => {
                               'application' => 'JavaHttpRef',
                               'group' => 'blue',
                               'cluster' => 'ci-appx',
                               'vip_fqdn' => 'ci-appx-vip.st.net.local',
                               'environment' => 'ci',
                               'port'        => '8000',
                               'dependencies' => {},
                               'application_dependant_instances' => [],
                               'participation_dependant_instances' => []
                             })
  end

  it 'generates app servers that are not part of a virtual service' do
    stack "blah" do
      standalone_appserver "appx" do
        self.application = "JavaHttpRef"
      end
    end

    env "ci", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "blah"
    end

    server = find("ci-appx-001.mgmt.st.net.local")
    server.to_enc.should eql('role::http_app' => {
                               'application' => 'JavaHttpRef',
                               'group' => 'blue',
                               'cluster' => 'ci-appx',
                               'environment' => 'ci',
                               'port'        => '8000',
                               'dependencies' => {},
                               'application_dependant_instances' => [],
                               'participation_dependant_instances' => []
                             })
  end

  it 'returns nil if asked for a machine that does not exist' do
    find("no-exist").should eql(nil)
  end

  it 'can build elastics search clusters' do
    stack "es" do
      elasticsearch do
      end
    end

    env "eg", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "es"
    end

    eg_es = find("eg-elasticsearch-001.mgmt.st.net.local")
    eg_es.to_enc['role::elasticsearch_node']['cluster_nodes'].should include(
      'eg-elasticsearch-002.st.net.local',
      'eg-elasticsearch-001.st.net.local')
    eg_es.to_enc['role::elasticsearch_node']['cluster_nodes'].size.should eql(2)
  end

  it 'configures NAT boxes to NAT incoming public IPs' do
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

    enc = find("eg-nat-001.mgmt.st.net.local").to_enc
    enc['role::natserver']['prod_virtual_router_id'].should eql(106)
    enc['role::natserver']['front_virtual_router_id'].should eql(105)

    snat = enc['role::natserver']['rules']['SNAT']
    snat['prod']['to_source'].should eql('nat-vip.front.st.net.local')

    dnat = enc['role::natserver']['rules']['DNAT']
    dnat.size.should eql(5)
    dnat_1 = dnat['eg-withnat-vip.front.st.net.local 80']
    dnat_1['dest_host'].should eql('eg-withnat-vip.st.net.local')
    dnat_1['dest_port'].should eql('80')
    dnat_1['tcp'].should eql('true')
    dnat_1['udp'].should eql('false')

    dnat_2 = dnat['eg-withnat-vip.front.st.net.local 443']
    dnat_2['dest_host'].should eql('eg-withnat-vip.st.net.local')
    dnat_2['dest_port'].should eql('443')
    dnat_2['tcp'].should eql('true')
    dnat_2['udp'].should eql('false')

    dnat_3 = dnat['eg-sftp-vip.front.st.net.local 21']
    dnat_3['dest_host'].should eql('eg-sftp-vip.st.net.local')
    dnat_3['dest_port'].should eql('21')
    dnat_3['tcp'].should eql('true')
    dnat_3['udp'].should eql('false')

    dnat_4 = dnat['eg-sftp-vip.front.st.net.local 22']
    dnat_4['dest_host'].should eql('eg-sftp-vip.st.net.local')
    dnat_4['dest_port'].should eql('22')
    dnat_4['tcp'].should eql('true')
    dnat_4['udp'].should eql('false')

    dnat_5 = dnat['eg-sftp-vip.front.st.net.local 2222']
    dnat_5['dest_host'].should eql('eg-sftp-vip.st.net.local')
    dnat_5['dest_port'].should eql('2222')
    dnat_5['tcp'].should eql('true')
    dnat_5['udp'].should eql('false')

    enc = find('sub-nat-001.mgmt.st.net.local').to_enc
    enc['role::natserver']['prod_virtual_router_id'].should eql(106)
    enc['role::natserver']['front_virtual_router_id'].should eql(105)

    snat = enc['role::natserver']['rules']['SNAT']
    snat['prod']['to_source'].should eql('nat-vip.front.st.net.local')

    dnat = enc['role::natserver']['rules']['DNAT']
    dnat.size.should eql(2)
    dnat_1 = dnat['sub-blahnat-vip.front.st.net.local 8008']
    dnat_1['dest_host'].should eql('sub-blahnat-vip.st.net.local')
    dnat_1['dest_port'].should eql('8008')
    dnat_1['tcp'].should eql('true')
    dnat_1['udp'].should eql('false')

    dnat_2 = dnat['sub-defaultport-vip.front.st.net.local 8000']
    dnat_2['dest_host'].should eql('sub-defaultport-vip.st.net.local')
    dnat_2['dest_port'].should eql('8000')
    dnat_2['tcp'].should eql('true')
    dnat_2['udp'].should eql('false')
  end

  it 'throws an error if we try and instantiate a stack that isnt defined' do
    expect do
      env "myold", :primary_site => "x", :secondary_site => "y" do
        instantiate_stack "no-exist"
      end
    end.to raise_error "no stack found 'no-exist'"
  end

  it 'can be converted to an array of machine_defs (actual machines)' do
    stack "mystack" do
      loadbalancer
      natserver
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "mystack"
    end

    find_environment("e1").flatten.map(&:name).should include("e1-lb-001", "e1-lb-002", "e1-nat-001", "e1-nat-002")
  end

  it 'can build forward proxy servers' do
    stack "mystack" do
      rate_limited_forward_proxy 's3proxy'
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "mystack"
    end

    find("e1-s3proxy-001.mgmt.space.net.local").to_enc.should eql('role::rate_limited_forward_proxy' => {})

    find("e1-s3proxy-001.mgmt.space.net.local").networks.should eql([:mgmt, :prod])
  end

  it 'things that are part of virtual services are given availability groups' do
    stack "mystack" do
      virtual_appserver "x"
      virtual_proxyserver "px"
      virtual_sftpserver "sx"
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "mystack"
    end

    find("e1-x-001.mgmt.space.net.local").availability_group.should eql("e1-x")
    find("e1-px-001.mgmt.space.net.local").availability_group.should eql("e1-px")
    find("e1-sx-001.mgmt.space.net.local").availability_group.should eql("e1-sx")
  end

  it 'adds ehcache settings to the enc if enable_ehcache is set inside a virtual_appserver' do
    stack "mystack" do
      virtual_appserver "x" do
        enable_ehcache
      end
    end

    env "e1", :primary_site => 'space' do
      instantiate_stack "mystack"
    end

    server = find("e1-x-001.mgmt.space.net.local")
    server.to_enc['role::http_app']['dependencies']['cache.peers'].should eql('["e1-x-002.space.net.local"]')
    server.to_enc['role::http_app']['dependencies']['cache.enabled'].should eql('true')
    server.to_enc['role::http_app']['dependencies']['cache.registryPort'].should eql('49000')
    server.to_enc['role::http_app']['dependencies']['cache.remoteObjectPort'].should eql('49010')
  end

  it 'allows specification of additional classes that should be included on the host' do
    stack "mystack" do
      virtual_appserver "x" do
        include_class 'test::puppet::class'
        each_machine do |_machine|
          include_class 'test::puppet::class2'
        end
      end
    end

    env "e1", :primary_site => 'space' do
      instantiate_stack "mystack"
    end

    server = find("e1-x-001.mgmt.space.net.local")
    server.to_enc.keys.include? 'test::puppet::class'
    server.to_enc.keys.include? 'test::puppet::class2'
  end

  it 'allows specification of aditional classes with additional parameters that should be included on the host' do
    stack "mystack" do
      virtual_appserver "x" do
        include_class 'test::puppet::class', 'test_key' => 'test_value'
        each_machine do |_machine|
          include_class 'test::puppet::class2', 'test_key2' => 'test_value2'
        end
      end
    end

    env "e1", :primary_site => 'space' do
      instantiate_stack "mystack"
    end

    server = find("e1-x-001.mgmt.space.net.local")
    server.to_enc['test::puppet::class'].should eql('test_key' => 'test_value')
    server.to_enc['test::puppet::class2'].should eql('test_key2' => 'test_value2')
  end
end
