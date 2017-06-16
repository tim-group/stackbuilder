require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'exampleproxy' do
  given do
    stack "exampleproxy" do
      proxy_service 'exampleproxy' do
        vhost('exampleapp')
        vhost('exampleapp2', 'example.overridden')
        vhost('exampleapp', 'example.absent') do
          absent
        end
        nat_config.dnat_enabled = true
        self.ports = [80, 443, 8443]
      end

      app_service 'exampleapp' do
        self.application = 'example'
      end

      app_service 'exampleapp2' do
        self.application = 'example'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "exampleproxy"
    end
  end

  host('e1-exampleproxy-001.mgmt.space.net.local') do |host|
    role_enc = host.to_enc['role::proxyserver']
    expect(role_enc['default_ssl_cert']).to eql('wildcard_timgroup_com')
    expect(role_enc['environment']).to eql('e1')
    expect(role_enc['prod_vip_fqdn']).to eql('e1-exampleproxy-vip.space.net.local')
    expect(role_enc['vhosts'].size).to eql(3)
    vhost1_enc = role_enc['vhosts']['e1-exampleproxy-vip.front.space.net.local']
    expect(vhost1_enc['ensure']).to eql('present')
    expect(vhost1_enc['proxy_pass_rules']).to eql('/' => 'http://e1-exampleapp-vip.space.net.local:8000')
    expect(vhost1_enc['aliases']).to include('e1-exampleproxy-vip.space.net.local')
    expect(vhost1_enc['aliases'].size).to eql(1)
    expect(vhost1_enc['application']).to eql('example')
    expect(vhost1_enc['cert']).to eql('wildcard_timgroup_com')

    vhost2_enc = role_enc['vhosts']['example.overridden']
    expect(vhost2_enc['proxy_pass_rules']).to eql('/' => 'http://e1-exampleapp2-vip.space.net.local:8000')
    expect(vhost2_enc['aliases']).to include(
      'e1-exampleproxy-vip.front.space.net.local',
      'e1-exampleproxy-vip.space.net.local'
    )
    expect(vhost2_enc['aliases'].size).to eql(2)
    expect(vhost2_enc['application']).to eql('example')
    expect(vhost2_enc['cert']).to eql('wildcard_timgroup_com')

    vhost3_enc = role_enc['vhosts']['example.absent']
    expect(vhost3_enc['ensure']).to eql('absent')
  end
end

describe_stack 'proxy servers can have the default ssl cert and vhost ssl certs overriden' do
  given do
    stack "exampleproxy" do
      proxy_service 'exampleproxy' do
        @cert = 'test_cert_change'
        vhost('exampleapp') do
          @cert = 'test_vhost_cert_change'
        end
        add_vip_network :front
      end

      app_service 'exampleapp' do
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
    expect(enc['role::proxyserver']['default_ssl_cert']).to eql('test_cert_change')
    expect(enc['role::proxyserver']['vhosts']['e1-exampleproxy-vip.front.space.net.local']['cert']).
      to eql('test_vhost_cert_change')
  end
end

describe_stack 'proxy pass rules without an environment default to the environment set (if any) of the vhost' do
  given do
    stack 'funds_proxy' do
      proxy_service 'fundsproxy' do
        @cert = 'wildcard_youdevise_com'
        vhost('fundsuserapp', 'funds-mirror.timgroup.com', 'mirror') do
          @cert = 'wildcard_timgroup_com'
          add_pass_rule "/HIP/resources", :service => "blondinapp", :environment => 'mirror'
          add_pass_rule "/HIP/blah", :service => "blondinapp", :environment => 'latest'
          add_pass_rule "/HIP/blah2", :service => "blondinapp", :environment => 'shared'
          add_pass_rule "/HIP/blah3", :service => "blondinapp"
        end
        nat_config.dnat_enabled = true
      end
    end
    stack 'funds' do
      app_service 'blondinapp' do
        self.groups = ['blue']
        self.application = 'Blondin'
      end

      app_service 'fundsuserapp' do
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
    expect(proxy_pass_rules['/']).to eql 'http://mirror-fundsuserapp-vip.oy.net.local:8000'
    expect(proxy_pass_rules['/HIP/resources']).to eql 'http://mirror-blondinapp-vip.oy.net.local:8000'
    expect(proxy_pass_rules['/HIP/blah']).to eql 'http://latest-blondinapp-vip.oy.net.local:8000'
    expect(proxy_pass_rules['/HIP/blah2']).to eql 'http://shared-blondinapp-vip.oy.net.local:8000'
    expect(proxy_pass_rules['/HIP/blah3']).to eql 'http://mirror-blondinapp-vip.oy.net.local:8000'
  end
end

describe_stack 'proxy servers can exist in multiple sites' do
  given do
    stack 'blondin' do
      app_service 'blondinapp' do
        self.application = 'Blondin'
        @enable_secondary_site = true
      end
    end
    stack 'funds_proxy' do
      proxy_service 'fundsproxy' do
        @enable_secondary_site = true
        @cert = 'wildcard_youdevise_com'
        vhost('fundsuserapp', 'funds-mirror.timgroup.com', 'shared') do
          @cert = 'wildcard_timgroup_com'
          add_pass_rule "/HIP/resources", :service => "blondinapp", :environment => 'shared'
        end
        nat_config.dnat_enabled = true
      end
    end
    stack 'funds' do
      app_service 'fundsuserapp' do
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
    expect(stack).to have_hosts(
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
    expect(role_enc['default_ssl_cert']).to eql('wildcard_youdevise_com')
    expect(role_enc['environment']).to eql('shared')
    expect(role_enc['prod_vip_fqdn']).to eql('shared-fundsproxy-vip.pg.net.local')
    expect(role_enc['vhosts'].size).to eql(1)
    vhost_enc = role_enc['vhosts']['funds-mirror.timgroup.com']
    expect(vhost_enc['proxy_pass_rules']).to eql('/HIP/resources' => 'http://shared-blondinapp-vip.pg.net.local:8000',
                                                 '/'              => 'http://shared-fundsuserapp-vip.pg.net.local:8000')
    expect(vhost_enc['aliases']).to include(
      'shared-fundsproxy-vip.front.pg.net.local',
      'shared-fundsproxy-vip.pg.net.local'
    )
    expect(vhost_enc['aliases'].size).to eql(2)
    expect(vhost_enc['application']).to eql('tfunds')
    expect(vhost_enc['cert']).to eql('wildcard_timgroup_com')
  end

  host('shared-fundsproxy-001.mgmt.oy.net.local') do |host|
    role_enc = host.to_enc['role::proxyserver']
    expect(role_enc['default_ssl_cert']).to eql('wildcard_youdevise_com')
    expect(role_enc['environment']).to eql('shared')
    expect(role_enc['prod_vip_fqdn']).to eql('shared-fundsproxy-vip.oy.net.local')
    expect(role_enc['vhosts'].size).to eql(1)
    vhost_enc = role_enc['vhosts']['funds-mirror.timgroup.com']
    expect(vhost_enc['proxy_pass_rules']).to eql('/HIP/resources' => 'http://shared-blondinapp-vip.oy.net.local:8000',
                                                 '/'              => 'http://shared-fundsuserapp-vip.oy.net.local:8000')
    expect(vhost_enc['aliases']).to include(
      'shared-fundsproxy-vip.front.oy.net.local',
      'shared-fundsproxy-vip.oy.net.local'
    )
    expect(vhost_enc['aliases'].size).to eql(2)
    expect(vhost_enc['application']).to eql('tfunds')
    expect(vhost_enc['cert']).to eql('wildcard_timgroup_com')
  end
end
describe_stack 'generates proxyserver enc data' do
  given do
    stack "ref" do
      app_service "refapp" do
        self.application = "MyApp"
      end
      app_service "ref2app" do
        self.application = "MyOtherApp"
      end
      app_service "downstreamapp"
      proxy_service "refproxy" do
        add_vip_network :front
        vhost('refapp') do
          @aliases << 'example.timgroup.com'
        end
        vhost('ref2app', 'example.timgroup.com') do
          add_pass_rule "/resources", :service => "downstreamapp"
        end
      end
    end

    stack 'ref2' do
      app_service "refapp3" do
      end
      proxy_service "refproxy2" do
        add_vip_network :front
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
    expect(role_enc['default_ssl_cert']).to eql('wildcard_timgroup_com')
    expect(role_enc['environment']).to eql('env')
    expect(role_enc['prod_vip_fqdn']).to eql('env-refproxy-vip.st.net.local')
    expect(role_enc['vhosts'].size).to eql(2)

    vhost_enc1 = role_enc['vhosts']['env-refproxy-vip.front.st.net.local']
    expect(vhost_enc1['proxy_pass_rules']).to eql('/' => 'http://env-refapp-vip.st.net.local:8000')
    expect(vhost_enc1['aliases']).to include('example.timgroup.com', 'env-refproxy-vip.st.net.local')
    expect(vhost_enc1['aliases'].size).to eql(2)
    expect(vhost_enc1['application']).to eql('MyApp')
    expect(vhost_enc1['cert']).to eql('wildcard_timgroup_com')

    vhost_enc2 = role_enc['vhosts']['example.timgroup.com']
    expect(vhost_enc2['proxy_pass_rules']).to eql('/'          => "http://env-ref2app-vip.st.net.local:8000",
                                                  '/resources' => "http://env-downstreamapp-vip.st.net.local:8000")
    expect(vhost_enc2['aliases']).to include('env-refproxy-vip.front.st.net.local', 'env-refproxy-vip.st.net.local')
    expect(vhost_enc2['aliases'].size).to eql(2)
    expect(vhost_enc2['application']).to eql('MyOtherApp')
    expect(vhost_enc2['cert']).to eql('wildcard_timgroup_com')
  end

  host("env2-refproxy2-001.mgmt.st.net.local") do |proxyserver|
    enc = proxyserver.to_enc['role::proxyserver']
    expect(enc['vhosts']['example2.timgroup.com']['proxy_pass_rules']['/somewhere']).to \
      eql 'http://env-downstreamapp-vip.st.net.local:8000'
  end
end

describe_stack 'generates proxy server enc data with persistent when enable_persistent is specified' do
  given do
    stack "loadbalancer" do
      loadbalancer_service
    end

    stack "proxyserver" do
      proxy_service "proxy" do
        enable_persistence '443'
        vhost('exampleapp') do
          use_for_lb_healthcheck
        end
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "loadbalancer"
      instantiate_stack "proxyserver"
    end
  end
  host("st-lb-001.mgmt.st.net.local") do |loadbalancer|
    lb_role_enc = loadbalancer.to_enc['role::loadbalancer']
    expect(lb_role_enc["virtual_router_id"]).to eql(1)
    expect(lb_role_enc["virtual_servers"].size).to eql(1)

    vserver_enc = lb_role_enc["virtual_servers"]['st-proxy-vip.st.net.local']

    expect(vserver_enc['type']).to eql('proxy')
    expect(vserver_enc['ports']).to eql([80, 443])
    expect(vserver_enc['realservers']['blue']).to eql(["st-proxy-001.st.net.local", "st-proxy-002.st.net.local"])
    expect(vserver_enc['persistent_ports']).to eql(['443'])
  end
end

describe_stack 'generates the correct proxy_pass rules when using override_vhost_location' do
  given do
    stack "test" do
      loadbalancer_service do
        @enable_secondary_site = true if %w(production).include? environment.name
      end
    end

    stack 'foo' do
      app_service 'blondinapp' do
        self.groups = ['blue']
        self.application = 'Blondin'
        depend_on 'foouserapp'
        @one_instance_in_lb = true
        @enable_secondary_site = true if %w(production).include? environment.name
      end
      app_service 'foouserapp' do
        self.groups = ['blue']
        self.application = 'tfoo'
        self.ports = [8443]
        enable_ajp('8009')
        enable_sso('8443')
        enable_tomcat_session_replication
        @enable_secondary_site = true if %w(production).include? environment.name
      end
    end
    stack 'foo_proxy' do
      proxy_service 'fooproxy' do
        @cert = 'wildcard_youdevise_com'
        @enable_secondary_site = true if %w(production).include? environment.name
        @override_vhost_location = { 'production' => :secondary_site } if environment.name == 'shared'
        vhost('foouserapp', 'foo-old.com', 'production') do
          @add_default_aliases = false
          @cert = 'wildcard_youdevise_com'
          case environment
          when 'shared'
            add_properties 'is_hip' => true
            add_pass_rule '/HIP/resources', :service => 'blondinapp'
          end
        end
        vhost('foouserapp', 'foo.fooexample.com', 'production') do
          @cert = 'wildcard_fooexample.com'
          add_pass_rule '/HIP/resources', :service => 'blondinapp'
        end
        case environment.name
        when 'shared'
          vhost('foouserapp', 'foo-mirror.fooexample.com', 'mirror') do
            @cert = 'wildcard_fooexample.com'
            add_pass_rule '/HIP/resources', :service => 'blondinapp'
          end
          vhost('foouserapp', 'foo-latest.fooexample.com', 'latest') do
            @cert = 'wildcard_fooexample.com'
            add_pass_rule '/HIP/resources', :service => 'blondinapp'
          end
        end
      end
    end

    env "production", :primary_site => "pg", :secondary_site => "oy" do
      instantiate_stack "foo_proxy"
      instantiate_stack "test"
      instantiate_stack "foo"
    end

    env "shared", :primary_site => "oy" do
      instantiate_stack "foo_proxy"

      env "latest", :primary_site => "oy"do
        instantiate_stack "test"
        instantiate_stack "foo"
      end

      env "mirror", :primary_site => "oy" do
        instantiate_stack "test"
        instantiate_stack "foo"
      end
    end
  end

  host("shared-fooproxy-001.mgmt.oy.net.local") do |proxy|
    vhosts = proxy.to_enc['role::proxyserver']['vhosts']
    expect(vhosts.size).to eql(4)
    expect(vhosts['foo-old.com']['proxy_pass_rules']['/']).to eql(
      'http://production-foouserapp-vip.oy.net.local:8000'
    )
    expect(vhosts['foo.fooexample.com']['proxy_pass_rules']['/HIP/resources']).to eql(
      'http://production-blondinapp-vip.oy.net.local:8000'
    )
    expect(vhosts['foo-mirror.fooexample.com']['proxy_pass_rules']['/']).to eql(
      'http://mirror-foouserapp-vip.oy.net.local:8000'
    )
    expect(vhosts['foo-mirror.fooexample.com']['proxy_pass_rules']['/HIP/resources']).to eql(
      'http://mirror-blondinapp-vip.oy.net.local:8000'
    )
    expect(vhosts['foo-latest.fooexample.com']['proxy_pass_rules']['/']).to eql(
      'http://latest-foouserapp-vip.oy.net.local:8000'
    )
    expect(vhosts['foo-latest.fooexample.com']['proxy_pass_rules']['/HIP/resources']).to eql(
      'http://latest-blondinapp-vip.oy.net.local:8000'
    )
  end
  host("production-fooproxy-001.mgmt.pg.net.local") do |proxy|
    vhosts = proxy.to_enc['role::proxyserver']['vhosts']
    expect(vhosts.size).to eql(2)
    expect(vhosts['foo-old.com']['proxy_pass_rules']['/']).to eql(
      'http://production-foouserapp-vip.pg.net.local:8000'
    )
    expect(vhosts['foo.fooexample.com']['proxy_pass_rules']['/HIP/resources']).to eql(
      'http://production-blondinapp-vip.pg.net.local:8000'
    )
  end
end

describe_stack 'generates the correct proxy_pass and add_pass rules when env not specified' do
  given do
    stack 'bse_api' do
      app_service 'bseapiapp' do
        self.application = 'bse'
      end
    end
    stack 'bse' do
      app_service 'bseapiapp' do
        self.application = 'bse'
      end
    end
    stack 'bse_proxy' do
      proxy_service 'bseproxy' do
        vhost('bseapp', 'foo.timgroup.com') do
          add_pass_rule '/api-external', :service => 'bseapiapp'
        end
      end
    end

    env "production", :primary_site => "pg", :secondary_site => "oy" do
      instantiate_stack 'bse'
      instantiate_stack 'bse_api'
      instantiate_stack 'bse_proxy'
    end
  end
  host("production-bseapiapp-001.mgmt.pg.net.local") do |app|
    enc = app.to_enc['role::http_app']
    expect(enc['application_dependant_instances']).to include(
      'production-bseproxy-001.pg.net.local',
      'production-bseproxy-002.pg.net.local'
    )
  end
end

describe_stack 'generates proxy server and load balancer enc data with a vhost specific for lb healthchecks' do
  given do
    stack "loadbalancer" do
      loadbalancer_service
    end

    stack "proxyserver" do
      proxy_service "proxy" do
        vhost('app') do
          use_for_lb_healthcheck
        end
      end
    end

    stack 'appserver' do
      app_service 'app' do
        self.application = 'app'
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "loadbalancer"
      instantiate_stack "proxyserver"
      instantiate_stack 'appserver'
    end
  end
  host('st-proxy-001.mgmt.st.net.local') do |proxyserver|
    vhost_enc = proxyserver.to_enc['role::proxyserver']['vhosts']['st-proxy-vip.st.net.local']
    expect(vhost_enc['used_for_lb_healthcheck']).to be true
  end

  host("st-lb-001.mgmt.st.net.local") do |loadbalancer|
    vserver_enc = loadbalancer.to_enc['role::loadbalancer']["virtual_servers"]['st-proxy-vip.st.net.local']
    expect(vserver_enc['type']).to eql('proxy')
    expect(vserver_enc['ports']).to eql([80, 443])
    expect(vserver_enc['realservers']['blue']).to eql(["st-proxy-001.st.net.local", "st-proxy-002.st.net.local"])
    expect(vserver_enc['vhost_for_healthcheck']).to eql 'st-proxy-vip.st.net.local'
  end
end

describe_stack 'fails if a proxy_service has no vhost thats configured to be used fo rlb healthchecks' do
  given do
    stack "loadbalancer" do
      loadbalancer_service
    end

    stack "proxyserver" do
      proxy_service "proxy" do
        vhost('app') do
        end
      end
    end

    stack 'appserver' do
      app_service 'app' do
        self.application = 'app'
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "loadbalancer"
      instantiate_stack "proxyserver"
      instantiate_stack 'appserver'
    end
  end

  host('st-proxy-001.mgmt.st.net.local') do |proxyserver|
    vhost_enc = proxyserver.to_enc['role::proxyserver']['vhosts']['st-proxy-vip.st.net.local']
    expect(vhost_enc['used_for_lb_healthcheck']).to be false
  end

  host("st-lb-001.mgmt.st.net.local") do |loadbalancer|
    expect do
      loadbalancer.to_enc
    end.to raise_error "No vhosts of service 'proxy' in environment 'st' are configured to be used for load balancer healthchecks"
  end
end

describe_stack 'fails if a proxy_service has more than one vhost thats configured to be used for lb healthchecks' do
  given do
    stack "loadbalancer" do
      loadbalancer_service
    end

    stack "proxyserver" do
      proxy_service "proxy" do
        vhost('app') do
          use_for_lb_healthcheck
        end
        vhost('app2') do
          use_for_lb_healthcheck
        end
      end
    end

    stack 'appserver' do
      app_service 'app' do
        self.application = 'app'
      end
      app_service 'app2' do
        self.application = 'app'
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "loadbalancer"
      instantiate_stack "proxyserver"
      instantiate_stack 'appserver'
    end
  end

  host('st-proxy-001.mgmt.st.net.local') do |proxyserver|
    vhost_enc = proxyserver.to_enc['role::proxyserver']['vhosts']['st-proxy-vip.st.net.local']
    expect(vhost_enc['used_for_lb_healthcheck']).to be true
  end

  host("st-lb-001.mgmt.st.net.local") do |loadbalancer|
    expect do
      loadbalancer.to_enc
    end.to raise_error "More than one vhost of service 'proxy' in environment 'st' are configured to be used for load balancer " \
                       "healthchecks: st-proxy-vip.st.net.local,st-proxy-vip.st.net.local"
  end
  describe_stack 'proxy servers have an option to specify logging to syslog' do
    given do
      stack "exampleproxy" do
        proxy_service 'exampleproxy' do
          vhost('exampleapp') do
            @log_to_syslog = true
          end
        end

        app_service 'exampleapp' do
          self.groups = ['blue']
          self.application = 'example'
        end
      end

      env "e1", :primary_site => "space" do
        instantiate_stack "exampleproxy"
      end
    end

    host("e1-exampleproxy-001.mgmt.space.net.local") do |host|
      vhosts = host.to_enc['role::proxyserver']['vhosts']
      expect(vhosts['e1-exampleproxy-vip.space.net.local']['log_to_syslog']).to eql(true)
    end
  end
end
describe_stack 'vhosts should adopt default cert from proxy_service' do
  given do
    stack "proxyserver" do
      proxy_service "proxy" do
        vhost('app') do
          @cert = 'super_cert'
        end
      end
    end
    stack 'appserver' do
      app_service 'app' do
        self.application = 'app'
      end
    end

    env "st", :primary_site => "st", :secondary_site => "bs" do
      instantiate_stack "proxyserver"
      instantiate_stack "appserver"
    end
  end

  host('st-proxy-001.mgmt.st.net.local') do |proxyserver|
    vhost_enc = proxyserver.to_enc['role::proxyserver']['vhosts']['st-proxy-vip.st.net.local']
    expect(vhost_enc['cert']).to eql 'super_cert'
  end
end
