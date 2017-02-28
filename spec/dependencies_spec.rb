require 'stackbuilder/stacks/environment'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack 'loadbalancer' do
      loadbalancer_service
    end
    stack 'example' do
      proxy_service 'exampleproxy' do
        vhost('exampleapp') do
          use_for_lb_healthcheck
        end
        nat_config.dnat_enabled = true
      end

      app_service 'exampleapp' do
        self.groups = ['blue']
        self.application = 'ExAmPLE'
      end

      app_service 'exampleapp2' do
        self.groups = ['blue']
        self.application = 'example2'
        depend_on 'exampleapp'
        depend_on 'exampledb'
      end
      app_service 'exampleapp2' do
        self.groups = ['blue']
        self.application = 'example2'
        depend_on 'exampleapp'
        depend_on 'exampledb'
      end
    end
    stack 'example_db' do
      legacy_mysql_cluster 'exampledb' do
        self.instances = 1
        self.database_name = 'example'
      end
    end

    env 'e1', :primary_site => 'space' do
      instantiate_stack 'example'
      instantiate_stack 'example_db'
      instantiate_stack 'loadbalancer'
    end
  end

  host('e1-lb-001.mgmt.space.net.local') do |host|
    rs = host.to_enc['role::loadbalancer']['virtual_servers']['e1-exampleapp-vip.space.net.local']['realservers']
    expect(rs['blue']).to eql(['e1-exampleapp-001.space.net.local', 'e1-exampleapp-002.space.net.local'])
    rs = host.to_enc['role::loadbalancer']['virtual_servers']['e1-exampleapp2-vip.space.net.local']['realservers']
    expect(rs['blue']).to eql(['e1-exampleapp2-001.space.net.local', 'e1-exampleapp2-002.space.net.local'])
  end

  host('e1-exampleproxy-001.mgmt.space.net.local') do |host|
    ppr = host.to_enc['role::proxyserver']['vhosts']['e1-exampleproxy-vip.front.space.net.local']['proxy_pass_rules']
    expect(ppr).to eql('/' => 'http://e1-exampleapp-vip.space.net.local:8000')
  end

  host('e1-exampleapp2-002.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::http_app']['application_dependant_instances']).to eql([
      'e1-lb-001.space.net.local',
      'e1-lb-002.space.net.local'
    ])
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['db.example.database']).to eql('example')
    expect(deps['db.example.hostname']).to eql('e1-exampledb-001.space.net.local')
    expect(deps['db.example.password_hiera_key']).to eql('e1/example2/mysql_password')
    expect(deps['db.example.username']).to eql('example2')
    expect(deps['example.url']).to eql('http://e1-exampleapp-vip.space.net.local:8000')
  end
  host('e1-exampleapp-002.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::http_app']['application_dependant_instances']).to eql([
      'e1-exampleapp2-001.space.net.local',
      'e1-exampleapp2-002.space.net.local',
      'e1-exampleproxy-001.space.net.local',
      'e1-exampleproxy-002.space.net.local',
      'e1-lb-001.space.net.local',
      'e1-lb-002.space.net.local'
    ])
    expect(host.to_enc['role::http_app']['dependencies']).to eql({})
  end
  host('e1-exampledb-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::databaseserver']['dependant_instances']).to eql([
      'e1-exampleapp2-001.space.net.local',
      'e1-exampleapp2-002.space.net.local'
    ])
    rights = host.to_enc['mysql_hacks::application_rights_wrapper']['rights']
    expect(rights['example2@e1-exampleapp2-001.space.net.local/example']).to eql(
      'password_hiera_key' => 'e1/example2/mysql_password')
    expect(rights['example2@e1-exampleapp2-002.space.net.local/example']).to eql(
      'password_hiera_key' => 'e1/example2/mysql_password')
  end
end

describe_stack 'stack with cross environment dependencies' do
  given do
    stack 'example' do
      app_service 'noconfigapp' do
        self.groups = ['blue']
        self.application = 'example'
        case environment.name
        when 'e1'
          depend_on 'noconfigapp', 'e2'
        when 'e2'
          depend_on 'noconfigapp', 'e1'
        end
      end
    end

    env 'e1', :primary_site => 'space' do
      instantiate_stack 'example'
    end

    env 'e2', :primary_site => 'earth' do
      instantiate_stack 'example'
    end
  end

  host('e2-noconfigapp-001.mgmt.earth.net.local') do |host|
    expect(host.to_enc['role::http_app']['application_dependant_instances']).to eql([
      'e1-noconfigapp-001.space.net.local',
      'e1-noconfigapp-002.space.net.local'
    ])
  end
  host('e1-noconfigapp-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::http_app']['application_dependant_instances']).to eql([
      'e2-noconfigapp-001.earth.net.local',
      'e2-noconfigapp-002.earth.net.local'
    ])
  end
end

describe_stack 'stack with sub environment dependencies' do
  given do
    stack 'blondin' do
      app_service 'blondinapp' do
        self.groups = ['blue']
        self.application = 'Blondin'
      end
    end

    stack 'funds' do
      app_service 'fundsuserapp' do
        self.groups = ['blue']
        self.application = 'tfunds'
        self.ports = [8443]
        enable_ajp('8009')
        enable_sso('8443')
        disable_http_lb_hack
      end
    end

    stack 'funds_proxy' do
      proxy_service 'fundsproxy' do
        @cert = 'wildcard_youdevise_com'
        case environment.name
        when 'shared'
          vhost('fundsuserapp', 'funds-mirror.timgroup.com', 'mirror') do
            @cert = 'wildcard_timgroup_com'
            add_pass_rule '/HIP/resources', :service => 'blondinapp', :environment => 'mirror'
          end
        end
        nat_config.dnat_enabled = true
      end
    end

    env 'shared',
        :primary_site => 'oy',
        :secondary_site => 'oy',
        :lb_virtual_router_id => 27 do
      instantiate_stack 'funds_proxy'

      env 'mirror',
          :timcyclic_instances => 1,
          :lb_virtual_router_id => 21 do
        instantiate_stack 'funds'
        instantiate_stack 'blondin'
      end
    end
  end
  host('mirror-blondinapp-001.mgmt.oy.net.local') do |host|
    expect(host.to_enc['role::http_app']['application_dependant_instances']).to include(
      'shared-fundsproxy-001.oy.net.local',
      'shared-fundsproxy-002.oy.net.local')
  end
end
