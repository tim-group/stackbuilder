require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'load balancers in multiple sites create the correct load balancing config in each site' do
  given do
    stack "lb" do
      loadbalancer  do
        @enable_secondary_site = true if %w(e1).include? environment.name
      end
    end

    stack "funds" do
      virtual_appserver 'fundsapp' do
        @enable_secondary_site = true if %w(e1).include? environment.name
      end
    end

    stack 'example' do
      virtual_appserver 'exampleapp' do
        self.application = 'example'
      end
    end

    env 'e1', primary_site: 'mars', secondary_site: 'jupiter' do
      instantiate_stack 'lb'
      instantiate_stack 'funds'
      instantiate_stack 'example'
    end

    env 'x1', primary_site: 'pluto', secondary_site: 'mercury' do
      instantiate_stack 'lb'
      instantiate_stack 'funds'
      instantiate_stack 'example'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    stack.should have_hosts(
      [
        'e1-lb-001.mgmt.mars.net.local',
        'e1-lb-002.mgmt.mars.net.local',
        'e1-lb-001.mgmt.jupiter.net.local',
        'e1-lb-002.mgmt.jupiter.net.local',
        'e1-fundsapp-001.mgmt.mars.net.local',
        'e1-fundsapp-002.mgmt.mars.net.local',
        'e1-fundsapp-001.mgmt.jupiter.net.local',
        'e1-fundsapp-002.mgmt.jupiter.net.local',
        'e1-exampleapp-001.mgmt.mars.net.local',
        'e1-exampleapp-002.mgmt.mars.net.local',
        'x1-fundsapp-001.mgmt.pluto.net.local',
        'x1-fundsapp-002.mgmt.pluto.net.local',
        'x1-lb-001.mgmt.pluto.net.local',
        'x1-lb-002.mgmt.pluto.net.local',
        'x1-exampleapp-001.mgmt.pluto.net.local',
        'x1-exampleapp-002.mgmt.pluto.net.local'
      ]
    )
  end
  host("e1-lb-001.mgmt.mars.net.local") do |host|
    virtual_servers = host.to_enc['role::loadbalancer']['virtual_servers']
    virtual_servers.keys.should include('e1-fundsapp-vip.mars.net.local')
    virtual_servers.keys.should include('e1-exampleapp-vip.mars.net.local')
    virtual_servers.size.should eql(2)
    vip = virtual_servers['e1-fundsapp-vip.mars.net.local']
    vip['realservers']['blue'].should eql(['e1-fundsapp-001.mars.net.local', 'e1-fundsapp-002.mars.net.local'])
  end
  host("e1-fundsapp-001.mgmt.mars.net.local") do |host|
    role = host.to_enc['role::http_app']
    role['application_dependant_instances'].should include('e1-lb-001.mars.net.local', 'e1-lb-002.mars.net.local')
    role['application_dependant_instances'].size.should eql(2)
  end
  host("e1-fundsapp-001.mgmt.jupiter.net.local") do |host|
    role = host.to_enc['role::http_app']
    role['application_dependant_instances'].should include('e1-lb-001.jupiter.net.local', 'e1-lb-002.jupiter.net.local')
    role['application_dependant_instances'].size.should eql(2)
  end
  host("e1-lb-001.mgmt.jupiter.net.local") do |host|
    virtual_servers = host.to_enc['role::loadbalancer']['virtual_servers']
    virtual_servers.keys.should include('e1-fundsapp-vip.jupiter.net.local')
    virtual_servers.size.should eql(1)
    vip = virtual_servers['e1-fundsapp-vip.jupiter.net.local']
    vip['realservers']['blue'].should eql(['e1-fundsapp-001.jupiter.net.local', 'e1-fundsapp-002.jupiter.net.local'])
  end
  host("x1-lb-001.mgmt.pluto.net.local") do |host|
    virtual_servers = host.to_enc['role::loadbalancer']['virtual_servers']
    virtual_servers.keys.should include('x1-fundsapp-vip.pluto.net.local')
    virtual_servers.keys.should include('x1-exampleapp-vip.pluto.net.local')
    virtual_servers.size.should eql(2)
  end
end

describe_stack 'load balancer stack create a secondary server with the correct enc and spec information' do
  given do
    stack "lb" do
      loadbalancer  do
        each_machine do |machine|
          machine.add_route('mgmt_pg_from_mgmt_oy')
        end
      end
    end

    stack 'fr' do
      virtual_appserver 'frapp' do
        enable_ehcache
        self.application = 'futuresroll'
        self.instances = 2
      end
    end

    env "e1", primary_site: "space", lb_virtual_router_id: 66 do
      instantiate_stack "lb"
      instantiate_stack "fr"
    end
  end

  host("e1-lb-002.mgmt.space.net.local") do |host|
    host.to_enc['role::loadbalancer']['virtual_router_id'].should eql(66)
    host.to_enc['role::loadbalancer']['virtual_servers']['e1-frapp-vip.space.net.local'].should eql(
      "env" => "e1",
      "monitor_warn" => 1,
      "app" => "futuresroll",
      "realservers" => {
        "blue" => ["e1-frapp-001.space.net.local", "e1-frapp-002.space.net.local"]
      },
      "healthcheck_timeout" => 10
    )
    host.to_enc['routes'].should eql("to" => ["mgmt_pg_from_mgmt_oy"])
    host.to_specs.shift[:qualified_hostnames].should eql(mgmt: "e1-lb-002.mgmt.space.net.local",
                                                         prod: "e1-lb-002.space.net.local")
    host.to_specs.shift[:availability_group].should eql('e1-lb')
    host.to_specs.shift[:networks].should eql([:mgmt, :prod])
    host.to_specs.shift[:hostname].should eql('e1-lb-002')
    host.to_specs.shift[:domain].should eql('space.net.local')
  end
end
describe_stack 'load balancer will generate config for a sub environment' do
  given do
    stack "lb" do
      loadbalancer
    end
    stack 'secureftp' do
      virtual_sftpserver 'sftp'
    end
    stack "proxystack" do
      virtual_proxyserver "myproxy"
    end

    stack "blahx" do
      virtual_appserver "appx" do
        self.application = "JavaHttpRef"
        self.groups = %w(blue green)
      end
    end

    stack 'blahy' do
      virtual_appserver "app2x" do
        self.application = "MySuperCoolApp"
      end
    end

    env "st", primary_site: "st", secondary_site: "bs" do
      instantiate_stack "lb"
      instantiate_stack "secureftp"
      env "ci" do
        instantiate_stack "lb"
        instantiate_stack "secureftp"
        instantiate_stack "blahx"
        instantiate_stack "blahy"
      end

      env "ci2" do
        instantiate_stack "blahx"
        instantiate_stack "blahy"
        instantiate_stack "proxystack"
      end
    end
  end

  host("st-lb-001.mgmt.st.net.local") do |st_loadbalancer|
    st_lb_role = st_loadbalancer.to_enc['role::loadbalancer']
    st_lb_role['virtual_router_id'].should eql(1)
    st_lb_role['virtual_servers'].size.should eql(4)

    vip_1 = st_lb_role['virtual_servers']['ci2-appx-vip.st.net.local']
    vip_1['env'].should eql('ci2')
    vip_1['app'].should eql('JavaHttpRef')
    vip_1['monitor_warn'].should eql(0)
    vip_1['healthcheck_timeout'].should eql(10)
    vip_1['realservers']['blue'].should eql(['ci2-appx-001.st.net.local'])
    vip_1['realservers']['green'].should eql(['ci2-appx-002.st.net.local'])

    vip_2 = st_lb_role['virtual_servers']['ci2-app2x-vip.st.net.local']
    vip_2['env'].should eql('ci2')
    vip_2['app'].should eql('MySuperCoolApp')
    vip_2['monitor_warn'].should eql(1)
    vip_2['healthcheck_timeout'].should eql(10)
    vip_2['realservers']['blue'].should eql(['ci2-app2x-001.st.net.local', 'ci2-app2x-002.st.net.local'])

    vip_3 = st_lb_role['virtual_servers']['ci2-myproxy-vip.st.net.local']
    vip_3['type'].should eql('proxy')
    vip_3['ports'].should eql([80, 443])
    vip_3['realservers']['blue'].should eql(['ci2-myproxy-001.st.net.local', 'ci2-myproxy-002.st.net.local'])

    vip_4 = st_lb_role['virtual_servers']['st-sftp-vip.st.net.local']
    vip_4['type'].should eql('sftp')
    vip_4['realservers']['blue'].should eql(["st-sftp-001.st.net.local", "st-sftp-002.st.net.local"])
    vip_4['persistent_ports'].should eql([])
  end

  host("ci-lb-001.mgmt.st.net.local") do |ci_loadbalancer|
    ci_lb_role = ci_loadbalancer.to_enc['role::loadbalancer']

    ci_lb_role['virtual_router_id'].should eql(1)
    ci_lb_role['virtual_servers'].size.should eql(3)
    vip_1 = ci_lb_role['virtual_servers']['ci-appx-vip.st.net.local']
    vip_1['env'].should eql('ci')
    vip_1['app'].should eql('JavaHttpRef')
    vip_1['monitor_warn'].should eql(0)
    vip_1['healthcheck_timeout'].should eql(10)
    vip_1['realservers']['blue'].should eql(['ci-appx-001.st.net.local'])
    vip_1['realservers']['green'].should eql(['ci-appx-002.st.net.local'])

    vip_2 = ci_lb_role['virtual_servers']['ci-app2x-vip.st.net.local']
    vip_2['env'].should eql('ci')
    vip_2['app'].should eql('MySuperCoolApp')
    vip_2['monitor_warn'].should eql(1)
    vip_2['healthcheck_timeout'].should eql(10)
    vip_2['realservers']['blue'].should eql(['ci-app2x-001.st.net.local', 'ci-app2x-002.st.net.local'])

    vip_3 = ci_lb_role['virtual_servers']['ci-sftp-vip.st.net.local']
    vip_3['type'].should eql('sftp')
    vip_3['realservers']['blue'].should eql(["ci-sftp-001.st.net.local", "ci-sftp-002.st.net.local"])
    vip_3['persistent_ports'].should eql([])
  end
end
