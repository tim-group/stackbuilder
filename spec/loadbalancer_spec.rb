require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'load balancers in multiple sites create the correct load balancing config in each site' do
  given do
    stack "lb" do
      loadbalancer_service  do
        @enable_secondary_site = true if %w(e1).include? environment.name
      end
    end

    stack "funds" do
      app_service 'fundsapp' do
        @enable_secondary_site = true if %w(e1).include? environment.name
      end
    end

    stack 'example' do
      app_service 'exampleapp' do
        self.application = 'example'
      end
    end

    env 'e1', :primary_site => 'mars', :secondary_site => 'jupiter' do
      instantiate_stack 'lb'
      instantiate_stack 'funds'
      instantiate_stack 'example'
    end

    env 'x1', :primary_site => 'pluto', :secondary_site => 'mercury' do
      instantiate_stack 'lb'
      instantiate_stack 'funds'
      instantiate_stack 'example'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
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
    expect(virtual_servers.keys).to include('e1-fundsapp-vip.mars.net.local')
    expect(virtual_servers.keys).to include('e1-exampleapp-vip.mars.net.local')
    expect(virtual_servers.size).to eql(2)
    vip = virtual_servers['e1-fundsapp-vip.mars.net.local']
    expect(vip['realservers']['blue']).to eql(['e1-fundsapp-001.mars.net.local', 'e1-fundsapp-002.mars.net.local'])
  end
  host("e1-fundsapp-001.mgmt.mars.net.local") do |host|
    role = host.to_enc['role::http_app']
    expect(role['application_dependant_instances']).to include('e1-lb-001.mars.net.local', 'e1-lb-002.mars.net.local')
    expect(role['application_dependant_instances'].size).to eql(2)
  end
  host("e1-fundsapp-001.mgmt.jupiter.net.local") do |host|
    role = host.to_enc['role::http_app']
    expect(role['application_dependant_instances']).to include('e1-lb-001.jupiter.net.local',
                                                               'e1-lb-002.jupiter.net.local')
    expect(role['application_dependant_instances'].size).to eql(2)
  end
  host("e1-lb-001.mgmt.jupiter.net.local") do |host|
    virtual_servers = host.to_enc['role::loadbalancer']['virtual_servers']
    expect(virtual_servers.keys).to include('e1-fundsapp-vip.jupiter.net.local')
    expect(virtual_servers.size).to eql(1)
    vip = virtual_servers['e1-fundsapp-vip.jupiter.net.local']
    expect(vip['realservers']['blue']).to eql(['e1-fundsapp-001.jupiter.net.local',
                                               'e1-fundsapp-002.jupiter.net.local'])
  end
  host("x1-lb-001.mgmt.pluto.net.local") do |host|
    virtual_servers = host.to_enc['role::loadbalancer']['virtual_servers']
    expect(virtual_servers.keys).to include('x1-fundsapp-vip.pluto.net.local')
    expect(virtual_servers.keys).to include('x1-exampleapp-vip.pluto.net.local')
    expect(virtual_servers.size).to eql(2)
  end
end

describe_stack 'load balancer stack create a secondary server with the correct enc and spec information' do
  given do
    stack "lb" do
      loadbalancer_service  do
        each_machine do |machine|
          machine.add_route('mgmt_pg_from_mgmt_oy')
        end
      end
    end

    stack 'fr' do
      app_service 'frapp' do
        enable_ehcache
        self.application = 'futuresroll'
        self.instances = 2
      end
    end

    env "e1", :primary_site => "space", :lb_virtual_router_id => 66 do
      instantiate_stack "lb"
      instantiate_stack "fr"
    end
  end

  host("e1-lb-002.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::loadbalancer']['virtual_router_id']).to eql(66)
    expect(host.to_enc['role::loadbalancer']['virtual_servers']['e1-frapp-vip.space.net.local']).to eql(
      "env" => "e1",
      "monitor_warn" => 1,
      "app" => "futuresroll",
      "realservers" => {
        "blue" => ["e1-frapp-001.space.net.local", "e1-frapp-002.space.net.local"]
      },
      "healthcheck_timeout" => 10
    )
    expect(host.to_enc['routes']['to']).to include 'mgmt_pg_from_mgmt_oy'
    expect(host.to_specs.shift[:qualified_hostnames]).to eql(:mgmt => "e1-lb-002.mgmt.space.net.local",
                                                             :prod => "e1-lb-002.space.net.local")
    expect(host.to_specs.shift[:availability_group]).to eql('e1-lb')
    expect(host.to_specs.shift[:networks]).to eql([:mgmt, :prod])
    expect(host.to_specs.shift[:hostname]).to eql('e1-lb-002')
    expect(host.to_specs.shift[:domain]).to eql('space.net.local')
  end
end
describe_stack 'load balancer will generate config for a sub environment' do
  given do
    stack "lb" do
      loadbalancer_service
    end
    stack 'secureftp' do
      sftp_service 'sftp'
    end
    stack "proxystack" do
      proxy_service "myproxy"
    end

    stack "blahx" do
      app_service "appx" do
        self.application = "JavaHttpRef"
        self.groups = %w(blue green)
      end
    end

    stack 'blahy' do
      app_service "app2x" do
        self.application = "MySuperCoolApp"
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
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
    expect(st_lb_role['virtual_router_id']).to eql(1)
    expect(st_lb_role['virtual_servers'].size).to eql(4)

    vip_1 = st_lb_role['virtual_servers']['ci2-appx-vip.st.net.local']
    expect(vip_1['env']).to eql('ci2')
    expect(vip_1['app']).to eql('JavaHttpRef')
    expect(vip_1['monitor_warn']).to eql(0)
    expect(vip_1['healthcheck_timeout']).to eql(10)
    expect(vip_1['realservers']['blue']).to eql(['ci2-appx-001.st.net.local'])
    expect(vip_1['realservers']['green']).to eql(['ci2-appx-002.st.net.local'])

    vip_2 = st_lb_role['virtual_servers']['ci2-app2x-vip.st.net.local']
    expect(vip_2['env']).to eql('ci2')
    expect(vip_2['app']).to eql('MySuperCoolApp')
    expect(vip_2['monitor_warn']).to eql(1)
    expect(vip_2['healthcheck_timeout']).to eql(10)
    expect(vip_2['realservers']['blue']).to eql(['ci2-app2x-001.st.net.local', 'ci2-app2x-002.st.net.local'])

    vip_3 = st_lb_role['virtual_servers']['ci2-myproxy-vip.st.net.local']
    expect(vip_3['type']).to eql('proxy')
    expect(vip_3['ports']).to eql([80, 443])
    expect(vip_3['realservers']['blue']).to eql(['ci2-myproxy-001.st.net.local', 'ci2-myproxy-002.st.net.local'])

    vip_4 = st_lb_role['virtual_servers']['st-sftp-vip.st.net.local']
    expect(vip_4['type']).to eql('sftp')
    expect(vip_4['realservers']['blue']).to eql(["st-sftp-001.st.net.local", "st-sftp-002.st.net.local"])
    expect(vip_4['persistent_ports']).to eql([])
  end

  host("ci-lb-001.mgmt.st.net.local") do |ci_loadbalancer|
    ci_lb_role = ci_loadbalancer.to_enc['role::loadbalancer']

    expect(ci_lb_role['virtual_router_id']).to eql(1)
    expect(ci_lb_role['virtual_servers'].size).to eql(3)
    vip_1 = ci_lb_role['virtual_servers']['ci-appx-vip.st.net.local']
    expect(vip_1['env']).to eql('ci')
    expect(vip_1['app']).to eql('JavaHttpRef')
    expect(vip_1['monitor_warn']).to eql(0)
    expect(vip_1['healthcheck_timeout']).to eql(10)
    expect(vip_1['realservers']['blue']).to eql(['ci-appx-001.st.net.local'])
    expect(vip_1['realservers']['green']).to eql(['ci-appx-002.st.net.local'])

    vip_2 = ci_lb_role['virtual_servers']['ci-app2x-vip.st.net.local']
    expect(vip_2['env']).to eql('ci')
    expect(vip_2['app']).to eql('MySuperCoolApp')
    expect(vip_2['monitor_warn']).to eql(1)
    expect(vip_2['healthcheck_timeout']).to eql(10)
    expect(vip_2['realservers']['blue']).to eql(['ci-app2x-001.st.net.local', 'ci-app2x-002.st.net.local'])

    vip_3 = ci_lb_role['virtual_servers']['ci-sftp-vip.st.net.local']
    expect(vip_3['type']).to eql('sftp')
    expect(vip_3['realservers']['blue']).to eql(["ci-sftp-001.st.net.local", "ci-sftp-002.st.net.local"])
    expect(vip_3['persistent_ports']).to eql([])
  end
end

describe_stack 'should only load balance for services in the same site' do
  given do
    stack "lb" do
      loadbalancer_service do
        self.instances = { 'pg' => 2, 'oy' => 2 }
      end
    end
    stack 'example' do
      app_service "appx" do
        self.application = "JavaHttpRef"
        self.instances = { 'oy' => 2 }
      end
      app_service "appy" do
        self.application = "JavaHttpRef"
        self.instances = 2
      end
    end
    stack 'rabbit' do
      rabbitmq_cluster 'rabbitmq'
    end
    stack 'proxy' do
      proxy_service 'eproxy' do
        vhost('appy')
      end
    end

    env "e1", :primary_site => "pg", :secondary_site => 'oy' do
      instantiate_stack("lb")
      instantiate_stack("example")
      instantiate_stack("rabbit")
      instantiate_stack("proxy")
    end
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-lb-001.mgmt.pg.net.local',
        'e1-lb-002.mgmt.pg.net.local',
        'e1-lb-001.mgmt.oy.net.local',
        'e1-lb-002.mgmt.oy.net.local',
        'e1-appx-001.mgmt.oy.net.local',
        'e1-appx-002.mgmt.oy.net.local',
        'e1-appy-001.mgmt.pg.net.local',
        'e1-appy-002.mgmt.pg.net.local',
        'e1-rabbitmq-001.mgmt.pg.net.local',
        'e1-rabbitmq-002.mgmt.pg.net.local',
        'e1-eproxy-001.mgmt.pg.net.local',
        'e1-eproxy-002.mgmt.pg.net.local'
      ]
    )
  end
  host("e1-lb-001.mgmt.oy.net.local") do |host|
    virtual_servers = host.to_enc['role::loadbalancer']['virtual_servers']
    expect(virtual_servers.keys.size).to eql(1)
    expect(virtual_servers.keys).to include('e1-appx-vip.oy.net.local')
  end
  host("e1-lb-001.mgmt.pg.net.local") do |host|
    virtual_servers = host.to_enc['role::loadbalancer']['virtual_servers']
    expect(virtual_servers.keys.size).to eql(3)
    expect(virtual_servers.keys).to include('e1-appy-vip.pg.net.local')
    expect(virtual_servers.keys).to include('e1-eproxy-vip.pg.net.local')
    expect(virtual_servers.keys).to include('e1-rabbitmq-vip.pg.net.local')
  end
end
