require 'stacks/test_framework'

describe_stack 'exampleproxy' do
  given do
    stack "exampleproxy" do
      virtual_proxyserver 'exampleproxy' do
        vhost('exampleapp')
        vhost('exampleapp2', 'example.overridden')
        enable_nat
        self.ports = [80, 443, 8443]
      end

      virtual_appserver 'exampleapp' do
        self.application = 'example'
      end

      virtual_appserver 'exampleapp2' do
        self.application = 'example'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "exampleproxy"
    end
  end

  host('e1-exampleproxy-001.mgmt.space.net.local') do |host|
    role_enc = host.to_enc['role::proxyserver']
    role_enc['default_ssl_cert'].should eql('wildcard_timgroup_com')
    role_enc['environment'].should eql('e1')
    role_enc['prod_vip_fqdn'].should eql('e1-exampleproxy-vip.space.net.local')
    role_enc['vhosts'].size.should eql(2)
    vhost1_enc = role_enc['vhosts']['e1-exampleproxy-vip.front.space.net.local']
    vhost1_enc['proxy_pass_rules'].should eql('/' => 'http://e1-exampleapp-vip.space.net.local:8000')
    vhost1_enc['aliases'].should include('e1-exampleproxy-vip.space.net.local')
    vhost1_enc['aliases'].size.should eql(1)
    vhost1_enc['application'].should eql('example')
    vhost1_enc['redirects'].size.should eql(0)
    vhost1_enc['type'].should eql('default')
    vhost1_enc['vhost_properties'].should eql({})
    vhost1_enc['cert'].should eql('wildcard_timgroup_com')

    vhost2_enc = role_enc['vhosts']['example.overridden']
    vhost2_enc['proxy_pass_rules'].should eql('/' => 'http://e1-exampleapp2-vip.space.net.local:8000')
    vhost2_enc['aliases'].should include(
      'e1-exampleproxy-vip.front.space.net.local',
      'e1-exampleproxy-vip.space.net.local'
    )
    vhost2_enc['aliases'].size.should eql(2)
    vhost2_enc['application'].should eql('example')
    vhost2_enc['redirects'].size.should eql(0)
    vhost2_enc['type'].should eql('default')
    vhost2_enc['vhost_properties'].should eql({})
    vhost2_enc['cert'].should eql('wildcard_timgroup_com')
  end
end

describe_stack 'proxy servers can have the default ssl cert and vhost ssl certs overriden' do
  given do
    stack "exampleproxy" do
      virtual_proxyserver 'exampleproxy' do
        @cert = 'test_cert_change'
        vhost('exampleapp') do
          @cert = 'test_vhost_cert_change'
        end
      end

      virtual_appserver 'exampleapp' do
        self.groups = ['blue']
        self.application = 'example'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "exampleproxy"
    end
  end

  host("e1-exampleproxy-001.mgmt.space.net.local") do |host|
    enc = host.to_enc
    enc['role::proxyserver']['default_ssl_cert'].should eql('test_cert_change')
    enc['role::proxyserver']['vhosts']['e1-exampleproxy-vip.front.space.net.local']['cert'].
      should eql('test_vhost_cert_change')
  end
end

describe_stack 'proxy pass rules without an environment default to the environment set (if any) of the vhost' do
  given do
    stack 'funds_proxy' do
      virtual_proxyserver 'fundsproxy' do
        @cert = 'wildcard_youdevise_com'
        vhost('fundsuserapp', 'funds-mirror.timgroup.com', 'mirror') do
          @cert = 'wildcard_timgroup_com'
          add_properties 'is_hip' => true
          add_pass_rule "/HIP/resources", :service => "blondinapp", :environment => 'mirror'
          add_pass_rule "/HIP/blah", :service => "blondinapp", :environment => 'latest'
          add_pass_rule "/HIP/blah2", :service => "blondinapp", :environment => 'shared'
          add_pass_rule "/HIP/blah3", :service => "blondinapp"
        end
        enable_nat
      end
    end
    stack 'funds' do
      virtual_appserver 'blondinapp' do
        self.groups = ['blue']
        self.application = 'Blondin'
      end

      virtual_appserver 'fundsuserapp' do
        self.groups = ['blue']
        self.application = 'tfunds'
        self.ports = [8443]
      end
    end
    env 'shared', :primary_site => 'oy' do
      instantiate_stack 'funds_proxy'
      instantiate_stack 'funds'

      env 'mirror' do
        instantiate_stack 'funds'
      end
      env 'latest' do
        instantiate_stack 'funds'
      end
    end
  end
  host('shared-fundsproxy-001.mgmt.oy.net.local') do |host|
    proxy_pass_rules = host.to_enc['role::proxyserver']['vhosts']['funds-mirror.timgroup.com']['proxy_pass_rules']
    proxy_pass_rules['/'].should eql 'http://mirror-fundsuserapp-vip.oy.net.local:8000'
    proxy_pass_rules['/HIP/resources'].should eql 'http://mirror-blondinapp-vip.oy.net.local:8000'
    proxy_pass_rules['/HIP/blah'].should eql 'http://latest-blondinapp-vip.oy.net.local:8000'
    proxy_pass_rules['/HIP/blah2'].should eql 'http://shared-blondinapp-vip.oy.net.local:8000'
    proxy_pass_rules['/HIP/blah3'].should eql 'http://mirror-blondinapp-vip.oy.net.local:8000'
  end
end

describe_stack 'proxy servers can exist in multiple sites' do
  given do
    stack 'blondin' do
      virtual_appserver 'blondinapp' do
        self.application = 'Blondin'
        @enable_secondary_site = true
      end
    end
    stack 'funds_proxy' do
      virtual_proxyserver 'fundsproxy' do
        @enable_secondary_site = true
        @cert = 'wildcard_youdevise_com'
        vhost('fundsuserapp', 'funds-mirror.timgroup.com', 'shared') do
          add_properties 'is_hip' => true
          add_pass_rule "/HIP/resources", :service => "blondinapp", :environment => 'shared'
        end
        enable_nat
      end
    end
    stack 'funds' do
      virtual_appserver 'fundsuserapp' do
        @enable_secondary_site = true
        self.application = 'tfunds'
      end
    end
    env 'shared', :primary_site => 'oy', :secondary_site => 'pg' do
      instantiate_stack 'blondin'
      instantiate_stack 'funds_proxy'
      instantiate_stack 'funds'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    stack.should have_hosts(
      [
        'shared-fundsproxy-001.mgmt.oy.net.local',
        'shared-fundsproxy-002.mgmt.oy.net.local',
        'shared-fundsproxy-001.mgmt.pg.net.local',
        'shared-fundsproxy-002.mgmt.pg.net.local',
        'shared-fundsuserapp-001.mgmt.oy.net.local',
        'shared-fundsuserapp-002.mgmt.oy.net.local',
        'shared-fundsuserapp-001.mgmt.pg.net.local',
        'shared-fundsuserapp-002.mgmt.pg.net.local',
        'shared-blondinapp-001.mgmt.pg.net.local',
        'shared-blondinapp-002.mgmt.pg.net.local',
        'shared-blondinapp-001.mgmt.oy.net.local',
        'shared-blondinapp-002.mgmt.oy.net.local'
      ]
    )
  end

  host('shared-fundsproxy-001.mgmt.pg.net.local') do |host|
    role_enc = host.to_enc['role::proxyserver']
    role_enc['default_ssl_cert'].should eql('wildcard_youdevise_com')
    role_enc['environment'].should eql('shared')
    role_enc['prod_vip_fqdn'].should eql('shared-fundsproxy-vip.pg.net.local')
    role_enc['vhosts'].size.should eql(1)
    vhost_enc = role_enc['vhosts']['funds-mirror.timgroup.com']
    vhost_enc['proxy_pass_rules'].should eql('/HIP/resources' => 'http://shared-blondinapp-vip.pg.net.local:8000',
                                             '/'              => 'http://shared-fundsuserapp-vip.pg.net.local:8000')
    vhost_enc['aliases'].should include(
      'shared-fundsproxy-vip.front.pg.net.local',
      'shared-fundsproxy-vip.pg.net.local'
    )
    vhost_enc['aliases'].size.should eql(2)
    vhost_enc['application'].should eql('tfunds')
    vhost_enc['redirects'].size.should eql(0)
    vhost_enc['type'].should eql('default')
    vhost_enc['vhost_properties'].should eql('is_hip' => true)
    vhost_enc['cert'].should eql('wildcard_timgroup_com')
  end

  host('shared-fundsproxy-001.mgmt.oy.net.local') do |host|
    role_enc = host.to_enc['role::proxyserver']
    role_enc['default_ssl_cert'].should eql('wildcard_youdevise_com')
    role_enc['environment'].should eql('shared')
    role_enc['prod_vip_fqdn'].should eql('shared-fundsproxy-vip.oy.net.local')
    role_enc['vhosts'].size.should eql(1)
    vhost_enc = role_enc['vhosts']['funds-mirror.timgroup.com']
    vhost_enc['proxy_pass_rules'].should eql('/HIP/resources' => 'http://shared-blondinapp-vip.oy.net.local:8000',
                                             '/'              => 'http://shared-fundsuserapp-vip.oy.net.local:8000')
    vhost_enc['aliases'].should include(
      'shared-fundsproxy-vip.front.oy.net.local',
      'shared-fundsproxy-vip.oy.net.local'
    )
    vhost_enc['aliases'].size.should eql(2)
    vhost_enc['application'].should eql('tfunds')
    vhost_enc['redirects'].size.should eql(0)
    vhost_enc['type'].should eql('default')
    vhost_enc['vhost_properties'].should eql('is_hip' => true)
    vhost_enc['cert'].should eql('wildcard_timgroup_com')
  end
end
describe_stack 'generates proxyserver enc data' do
  given do
    stack "ref" do
      virtual_appserver "refapp" do
        self.application = "MyApp"
      end
      virtual_appserver "ref2app" do
        self.application = "MyOtherApp"
      end
      virtual_appserver "downstreamapp"
      virtual_proxyserver "refproxy" do
        vhost('refapp') do
          @aliases << 'example.timgroup.com'
          with_redirect "old-example.timgroup.com"
        end
        vhost('ref2app', 'example.timgroup.com') do
          add_pass_rule "/resources", :service => "downstreamapp"
        end
      end
    end

    stack 'ref2' do
      virtual_appserver "refapp3" do
      end
      virtual_proxyserver "refproxy2" do
        vhost('refapp3', 'example2.timgroup.com') do
          add_pass_rule "/somewhere", :service => "downstreamapp", :environment => 'env'
        end
      end
    end
    env "env", :primary_site => "st" do
      instantiate_stack "ref"
    end
    env "env2", :primary_site => "st" do
      instantiate_stack "ref2"
    end
  end

  host('env-refproxy-001.mgmt.st.net.local') do |proxyserver|
    role_enc = proxyserver.to_enc['role::proxyserver']
    role_enc['default_ssl_cert'].should eql('wildcard_timgroup_com')
    role_enc['environment'].should eql('env')
    role_enc['prod_vip_fqdn'].should eql('env-refproxy-vip.st.net.local')
    role_enc['vhosts'].size.should eql(2)

    vhost_enc1 = role_enc['vhosts']['env-refproxy-vip.front.st.net.local']
    vhost_enc1['proxy_pass_rules'].should eql('/' => 'http://env-refapp-vip.st.net.local:8000')
    vhost_enc1['aliases'].should include('example.timgroup.com', 'env-refproxy-vip.st.net.local')
    vhost_enc1['aliases'].size.should eql(2)
    vhost_enc1['application'].should eql('MyApp')
    vhost_enc1['redirects'].should include('old-example.timgroup.com')
    vhost_enc1['redirects'].size.should eql(1)
    vhost_enc1['type'].should eql('default')
    vhost_enc1['vhost_properties'].should eql({})
    vhost_enc1['cert'].should eql('wildcard_timgroup_com')

    vhost_enc2 = role_enc['vhosts']['example.timgroup.com']
    vhost_enc2['proxy_pass_rules'].should eql('/'          => "http://env-ref2app-vip.st.net.local:8000",
                                              '/resources' => "http://env-downstreamapp-vip.st.net.local:8000")
    vhost_enc2['aliases'].should include('env-refproxy-vip.front.st.net.local', 'env-refproxy-vip.st.net.local')
    vhost_enc2['aliases'].size.should eql(2)
    vhost_enc2['application'].should eql('MyOtherApp')
    vhost_enc2['redirects'].size.should eql(0)
    vhost_enc2['type'].should eql('default')
    vhost_enc2['vhost_properties'].should eql({})
    vhost_enc2['cert'].should eql('wildcard_timgroup_com')
  end

  host("env2-refproxy2-001.mgmt.st.net.local") do |proxyserver|
    enc = proxyserver.to_enc['role::proxyserver']
    enc['vhosts']['example2.timgroup.com']['proxy_pass_rules']['/somewhere'].should \
      eql 'http://env-downstreamapp-vip.st.net.local:8000'
  end
end

describe_stack 'generates proxy server enc data with persistent when enable_persistent is specified' do
  given do
    stack "loadbalancer" do
      loadbalancer
    end

    stack "proxyserver" do
      virtual_proxyserver "proxy" do
        enable_persistence '443'
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "loadbalancer"
      instantiate_stack "proxyserver"
    end
  end
  host("st-lb-001.mgmt.st.net.local") do |loadbalancer|
    lb_role_enc = loadbalancer.to_enc['role::loadbalancer']
    lb_role_enc["virtual_router_id"].should eql(1)
    lb_role_enc["virtual_servers"].size.should eql(1)
    vserver_enc = lb_role_enc["virtual_servers"]['st-proxy-vip.st.net.local']
    vserver_enc['type'].should eql('proxy')
    vserver_enc['ports'].should eql([80, 443])
    vserver_enc['realservers']['blue'].should eql(["st-proxy-001.st.net.local", "st-proxy-002.st.net.local"])
    vserver_enc['persistent_ports'].should eql(['443'])
  end
end
