require 'stackbuilder/stacks/environment'
require 'stackbuilder/stacks/factory'
require 'test_classes'
require 'spec_helper'
require 'stacks/test_framework'

describe 'stack-with-dependencies' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:dns_resolver) { AllocatingDnsResolver.new }
  let(:hiera_provider) { TestHieraProvider.new('stacks/application_credentials_selector' => 0) }

  let(:factory) do
    eval_stacks do
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

        app_service 'kubeexampleapp', :kubernetes => true do
          self.maintainers = [person('Test')]
          self.description = 'Check dependency evaluation for k8s apps'
          self.alerts_channel = 'test'
          self.groups = ['blue']
          self.application = 'kubeexample'
          self.instances = 1
          self.startup_alert_threshold = '1h'
          depend_on 'exampledb'
          depend_on 'exampleapp'
        end

        app_service 'exampleapp-with-k8s-dependency' do
          self.groups = ['blue']
          self.application = 'exampleapp'
          depend_on 'kubeexampleapp'
        end

        standard_service 'otherservice' do
          self.database_username = 'other'
          depend_on 'exampledb'
        end
      end
      stack 'example_db' do
        mysql_cluster 'exampledb' do
          self.instances = 1
          self.database_name = 'example'
          self.role_in_name = false
          self.backup_instances = 0
          self.slave_instances = 0
        end
      end

      env 'e1', :primary_site => 'space' do
        instantiate_stack 'example'
        instantiate_stack 'example_db'
        instantiate_stack 'loadbalancer'
      end
    end
  end

  it 'presents the correct config port for k8s app vips' do
    host = factory.inventory.find('e1-exampleapp-with-k8s-dependency-001.mgmt.space.net.local')
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['kubeexample.url']).to eql('http://e1-kubeexampleapp-vip.space.net.local')
  end

  it 'configures the loadbalancer' do
    host = factory.inventory.find('e1-lb-001.mgmt.space.net.local')

    rs = host.to_enc['role::loadbalancer']['virtual_servers']['e1-exampleapp-vip.space.net.local']['realservers']
    expect(rs['blue']).to eql(['e1-exampleapp-001.space.net.local', 'e1-exampleapp-002.space.net.local'])
    rs = host.to_enc['role::loadbalancer']['virtual_servers']['e1-exampleapp2-vip.space.net.local']['realservers']
    expect(rs['blue']).to eql(['e1-exampleapp2-001.space.net.local', 'e1-exampleapp2-002.space.net.local'])
  end

  it 'configures the proxy' do
    host = factory.inventory.find('e1-exampleproxy-001.mgmt.space.net.local')

    ppr = host.to_enc['role::proxyserver']['vhosts']['e1-exampleproxy-vip.front.space.net.local']['proxy_pass_rules']
    expect(ppr).to eql('/' => 'http://e1-exampleapp-vip.space.net.local:8000')
  end

  it 'configures a VM app server' do
    app = factory.inventory.find('e1-exampleapp-002.mgmt.space.net.local')
    app2 = factory.inventory.find('e1-exampleapp2-002.mgmt.space.net.local')

    expect(app2.to_enc['role::http_app']['application_dependant_instances']).to eql([
      'e1-lb-001.space.net.local',
      'e1-lb-002.space.net.local'
    ])
    deps = app2.to_enc['role::http_app']['dependencies']
    expect(deps['db.example.database']).to eql('example')
    expect(deps['db.example.hostname']).to eql('e1-exampledb-001.space.net.local')
    expect(deps['db.example.password_hiera_key']).to eql('e1/example2/mysql_password')
    expect(deps['db.example.username']).to eql('example2')
    expect(deps['example.url']).to eql('http://e1-exampleapp-vip.space.net.local:8000')

    expect(app.to_enc['role::http_app']['application_dependant_instances']).to eql([
      'e1-exampleapp2-001.space.net.local',
      'e1-exampleapp2-002.space.net.local',
      'e1-exampleproxy-001.space.net.local',
      'e1-exampleproxy-002.space.net.local',
      'e1-lb-001.space.net.local',
      'e1-lb-002.space.net.local'
    ])
    expect(app.to_enc['role::http_app']['dependencies']).to eql({})
    expect(app.to_enc['role::http_app']['allow_kubernetes_clusters']).to eql(['space'])
  end

  it 'configures a K8s app pod' do
    set = factory.inventory.find_environment('e1').definitions['example'].k8s_machinesets['kubeexampleapp']

    config = set.to_k8s(app_deployer, dns_resolver, hiera_provider).flat_map(&:resources).find { |s| s['kind'] == 'ConfigMap' }

    expect(config['data']['config.properties']).to match(/username=e1kubeexamplea0/)
    expect(config['data']['config.properties']).to match(/password={SECRET:e1_kubeexample_mysql_passwords_0/)
  end

  it 'configures the db' do
    host = factory.inventory.find('e1-exampledb-001.mgmt.space.net.local')

    rights = host.to_enc['mysql_hacks::application_rights_wrapper']['rights']
    expect(rights['example2@e1-exampleapp2-001.space.net.local/example']).to eql(
      'password_hiera_key' => 'e1/example2/mysql_password',
      'passwords_hiera_key' => 'e1/example2/mysql_passwords')
    expect(rights['example2@e1-exampleapp2-002.space.net.local/example']).to eql(
      'password_hiera_key' => 'e1/example2/mysql_password',
      'passwords_hiera_key' => 'e1/example2/mysql_passwords')
    expect(rights['e1kubeexamplea@space-e1-kubeexampleapp/example']).to eql(
      'password_hiera_key' => 'e1/kubeexample/mysql_password',
      'passwords_hiera_key' => 'e1/kubeexample/mysql_passwords',
      'allow_kubernetes_clusters' => ['space'])
    expect(rights['other@e1-otherservice-001.space.net.local/example']).to eql(
      'password_hiera_key' => 'e1/other/mysql_password',
      'passwords_hiera_key' => 'e1/other/mysql_passwords')
  end
end

describe_stack 'k8s app with non-k8s app dependency in same environment' do
  given do
    stack 'example' do
      app_service 'k8sapp', :kubernetes => true do
        self.application = 'example'
        depend_on 'nonk8sapp'
      end
      app_service 'nonk8sapp' do
        self.application = 'example'
      end
    end

    env 'e1', :primary_site => 'space' do
      instantiate_stack 'example'
    end
  end

  host('e1-nonk8sapp-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::http_app']['allow_kubernetes_clusters']).to eql(['space'])
  end
end

describe_stack 'k8s app with non-k8s app dependency which has instances in multiple sites' do
  given do
    stack 'example' do
      app_service 'k8sapp', :kubernetes => true do
        self.application = 'example'
        depend_on 'nonk8sapp'
      end
      app_service 'nonk8sapp' do
        self.application = 'example'
        self.instances = {
          'space' => 1,
          'earth' => 1
        }
      end
    end

    env 'e1', :primary_site => 'space', :secondary_site => 'earth' do
      instantiate_stack 'example'
    end
  end

  host('e1-nonk8sapp-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::http_app']['allow_kubernetes_clusters']).to eql(['space'])
  end

  host('e1-nonk8sapp-001.mgmt.earth.net.local') do |host|
    expect(host.to_enc['role::http_app']['allow_kubernetes_clusters']).to eql([])
  end
end

describe_stack 'k8s app with non-k8s app dependency in different env with multiple sites' do
  given do
    stack 'example-k8s' do
      app_service 'k8sapp', :kubernetes => true do
        self.application = 'example'
        depend_on 'nonk8sapp', 'e1'
      end
    end
    stack 'example-nonk8s' do
      app_service 'nonk8sapp' do
        self.application = 'example'
        self.instances = {
          'space' => 1,
          'earth' => 1
        }
      end
    end

    env 'e1', :primary_site => 'space', :secondary_site => 'earth' do
      instantiate_stack 'example-nonk8s'
    end
    env 'e2', :primary_site => 'earth' do
      instantiate_stack 'example-k8s'
    end
  end

  host('e1-nonk8sapp-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::http_app']['allow_kubernetes_clusters']).to eql([])
  end

  host('e1-nonk8sapp-001.mgmt.earth.net.local') do |host|
    expect(host.to_enc['role::http_app']['allow_kubernetes_clusters']).to eql(['earth'])
  end
end

describe_stack 'k8s app with non-k8s app dependency in different env with different site' do
  given do
    stack 'example-k8s' do
      app_service 'k8sapp', :kubernetes => true do
        self.application = 'example'
        depend_on 'nonk8sapp', 'e1'
      end
    end
    stack 'example-nonk8s' do
      app_service 'nonk8sapp' do
        self.application = 'example'
        self.instances = 1
      end
    end

    env 'e1', :primary_site => 'space' do
      instantiate_stack 'example-nonk8s'
    end
    env 'e2', :primary_site => 'earth' do
      instantiate_stack 'example-k8s'
    end
  end

  host('e1-nonk8sapp-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::http_app']['allow_kubernetes_clusters']).to eql(['earth'])
  end
end

describe_stack 'k8s app with non-k8s app dependency in different env with different site specified as hash' do
  given do
    stack 'example-k8s' do
      app_service 'k8sapp', :kubernetes => true do
        self.application = 'example'
        depend_on 'nonk8sapp', 'e1'
      end
    end
    stack 'example-nonk8s' do
      app_service 'nonk8sapp' do
        self.application = 'example'
        self.instances = {
          'space' => 1
        }
      end
    end

    env 'e1', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example-nonk8s'
    end
    env 'e2', :primary_site => 'earth' do
      instantiate_stack 'example-k8s'
    end
  end

  host('e1-nonk8sapp-001.mgmt.space.net.local') do |host|
    expect(host.to_enc['role::http_app']['allow_kubernetes_clusters']).to eql(['earth'])
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
        self.ports = {
          'sso' => {
            'port' => 8443
          }
        }
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

describe 'an app with dependencies fulfilled by more than 1 target' do
  let(:factory) do
    eval_stacks do
      stack 'example' do
        app_service 'exampleapp' do
          self.groups = ['blue']
          self.application = 'example'

          depend_on ['vm-instance', 'k8s-instance']
        end

        app_service 'vm-instance' do
          self.groups = ['blue']
          self.application = 'migratory'
        end

        app_service 'k8s-instance', :kubernetes => true do
          self.maintainers = [person('Test')]
          self.description = 'Check dependency evaluation for k8s apps'
          self.alerts_channel = 'test'
          self.groups = ['blue']
          self.application = 'migratory'
          self.instances = 1
          self.startup_alert_threshold = '1h'
        end
      end

      env 'e1', :primary_site => 'space' do
        instantiate_stack 'example'
      end
    end
  end

  it 'split the dependencies between the app instances' do
    app = factory.inventory.find('e1-exampleapp-001.mgmt.space.net.local')
    app2 = factory.inventory.find('e1-exampleapp-002.mgmt.space.net.local')

    deps = app.to_enc['role::http_app']['dependencies']
    deps2 = app2.to_enc['role::http_app']['dependencies']

    expect(deps['migratory.url']).to eql('http://e1-vm-instance-vip.space.net.local:8000')
    expect(deps2['migratory.url']).to eql('http://e1-k8s-instance-vip.space.net.local')
  end
end
