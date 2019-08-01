require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'
require 'test_classes'
require 'spec_helper'

describe_stack 'stack-with-dependencies' do
  given do
    stack 'example_db_depended_on_in_different_ways' do
      mysql_cluster 'exampledb' do
        self.role_in_name = false
        self.database_name = 'exampledb'
        self.master_instances = 2
        self.slave_instances = 3
        self.secondary_site_slave_instances = 1
        self.include_master_in_read_only_cluster = false
        self.supported_requirements = {
          :master_with_slaves => %w(
            e-exampledb-001.earth.net.local
            e-exampledb-003.earth.net.local
            e-exampledb-004.earth.net.local
          ),
          :read_only => %w(
            e-exampledb-003.earth.net.local
            e-exampledb-004.earth.net.local
          )
        }
      end
    end

    stack 'master_with_slaves_example' do
      app_service 'myapp' do
        self.groups = ['blue']
        self.application = 'rw-app'
        self.use_ha_mysql_ordering = true
        depend_on 'exampledb', environment.name, :master_with_slaves
      end
    end

    stack 'read_only_example' do
      app_service 'myroapp' do
        self.groups = ['blue']
        self.application = 'ro-app'
        depend_on 'exampledb', environment.name, :read_only
      end
    end

    env 'e', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example_db_depended_on_in_different_ways'
      instantiate_stack 'master_with_slaves_example'
      instantiate_stack 'read_only_example'
    end
  end

  host('e-myapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.hostname']).to eql('e-exampledb-001.earth.net.local')
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local")
  end

  host('e-myapp-002.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.hostname']).to eql('e-exampledb-001.earth.net.local')
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-004.earth.net.local,e-exampledb-003.earth.net.local")
  end

  host('e-myroapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.hostname']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local")
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local")
  end

  host('e-myroapp-002.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.hostname']).to eql('e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local')
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local")
  end
end

describe_stack 'mysql-cluster' do
  given do
    stack 'example_db_cluster' do
      mysql_cluster 'exampledb' do
        self.role_in_name = false
        self.database_name = 'exampledb'
        self.master_instances = 1
        self.slave_instances = 1
        self.secondary_site_slave_instances = 1
      end
    end

    env 'e', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example_db_cluster'
    end
  end

  host('e-exampledb-001.mgmt.space.net.local') do |host|
    expect(host.dependencies_inside_service.map(&:mgmt_fqdn).sort).to eql(
      [
        'e-exampledb-001.mgmt.earth.net.local',
        'e-exampledb-002.mgmt.earth.net.local',
        'e-exampledbbackup-001.mgmt.space.net.local'
      ])
  end
end

describe_stack 'stack-with-dependencies1' do
  given do
    stack 'example_db' do
      mysql_cluster 'exampledb' do
        self.role_in_name = false
        self.database_name = 'exampledb'
        self.master_instances = 2
        self.slave_instances = 3
        self.secondary_site_slave_instances = 1
        self.include_master_in_read_only_cluster = false
        self.supported_requirements = {
          :master_with_slaves => %w(
            e-exampledb-001.earth.net.local
            e-exampledb-003.earth.net.local
            e-exampledb-004.earth.net.local
            e-exampledb-005.earth.net.local
          ),
          :read_only => %w(
            e-exampledb-003.earth.net.local
            e-exampledb-004.earth.net.local
            e-exampledb-005.earth.net.local
          )
        }
      end
    end

    stack 'example_app' do
      app_service 'myharoapp' do
        self.groups = ['blue']
        self.application = 'ha-ro-app'
        self.use_ha_mysql_ordering = true
        self.instances = 4
        depend_on 'exampledb', environment.name, :read_only
      end
    end

    env 'e', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example_db'
      instantiate_stack 'example_app'
    end
  end

  host('e-myharoapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local")
  end

  host('e-myharoapp-002.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local,e-exampledb-003.earth.net.local")
  end

  host('e-myharoapp-003.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-005.earth.net.local,e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local")
  end

  host('e-myharoapp-004.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local")
  end
end

describe_stack 'stack-with-dependencies1' do
  given do
    stack 'example_db' do
      mysql_cluster 'exampledb' do
        self.role_in_name = false
        self.include_master_in_read_only_cluster = false
        self.database_name = 'exampledb'
        self.master_instances = 2
        self.slave_instances = 3
      end
    end

    stack 'example_app' do
      app_service 'myharoapp' do
        self.groups = ['blue']
        self.application = 'ha-ro-app'
        self.use_ha_mysql_ordering = true
        self.instances = 4
        depend_on 'exampledb'
      end
    end

    env 'e', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example_db'
      instantiate_stack 'example_app'
    end
  end

  host('e-myharoapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local")
  end

  host('e-myharoapp-002.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local,e-exampledb-003.earth.net.local")
  end

  host('e-myharoapp-003.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-005.earth.net.local,e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local")
  end

  host('e-myharoapp-004.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local")
  end
end

describe_stack 'stack-with-dependencies1' do
  given do
    stack 'example_db' do
      mysql_cluster 'exampledb' do
        self.role_in_name = false
        self.include_master_in_read_only_cluster = false
        self.database_name = 'exampledb'
        self.master_instances = 2
        self.slave_instances = 3
      end
    end

    stack 'example_app' do
      app_service 'myharoapp' do
        self.groups = ['blue']
        self.application = 'ha-ro-app'
        self.use_ha_mysql_ordering = true
        self.ha_mysql_ordering_exclude = %(exampledb)
        self.instances = 4
        depend_on 'exampledb'
      end
    end

    env 'e', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example_db'
      instantiate_stack 'example_app'
    end
  end

  host('e-myharoapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    deps['db.exampledb.read_only_cluster']
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local")
  end

  host('e-myharoapp-002.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    deps['db.exampledb.read_only_cluster']
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local")
  end

  host('e-myharoapp-003.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    deps['db.exampledb.read_only_cluster']
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local")
  end

  host('e-myharoapp-004.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local,e-exampledb-005.earth.net.local")
  end
end

describe 'k8s stack-with-dependencies' do
  let(:app_deployer) { TestAppDeployer.new('1.2.3') }
  let(:dns_resolver) do
    MyTestDnsResolver.new('e-myapp-vip.earth.net.local' => '3.1.4.1',
                          'e-exampledb-001.earth.net.local' => '3.1.4.2',
                          'e-exampledb-002.earth.net.local' => '3.1.4.3',
                          'e-exampledb-003.earth.net.local' => '3.1.4.4',
                          'e-exampledb-004.earth.net.local' => '3.1.4.5',
                          'e-exampledb-005.earth.net.local' => '3.1.4.6')
  end
  let(:hiera_provider) do
    TestHieraProvider.new(
      'stacks/application_credentials_selector' => 0,
      'kubernetes/hosts/space' => [],
      'kubernetes/hosts/earth' => []
    )
  end

  it 'example_db_depended_on_in_different_ways' do
    factory = eval_stacks do
      stack 'master_with_slaves_example' do
        mysql_cluster 'exampledb' do
          self.role_in_name = false
          self.database_name = 'exampledb'
          self.master_instances = 2
          self.slave_instances = 3
          self.secondary_site_slave_instances = 1
          self.include_master_in_read_only_cluster = false
        end
        app_service 'myapp', :kubernetes => true do
          self.groups = ['blue']
          self.application = 'rw-app'
          self.use_ha_mysql_ordering = true
          depend_on 'exampledb', environment.name
        end
      end
      env 'e', :primary_site => 'earth', :secondary_site => 'space' do
        instantiate_stack 'master_with_slaves_example'
      end
    end

    machine_sets = factory.inventory.find_environment('e').definitions['master_with_slaves_example'].k8s_machinesets
    k8s = machine_sets['myapp'].to_k8s(app_deployer, dns_resolver, hiera_provider)

    network_policies = k8s.resources.select do |policy|
      policy['kind'] == "NetworkPolicy"
    end

    expect(network_policies.size).to eq(2)
    expect(network_policies[1]['metadata']['name']).to eql('allow-myapp-out-to-e-exampledb-3306')
    egress = network_policies[1]['spec']['egress']
    expect(egress.size).to eq(1)
    expect(egress.first['to'].size).to eq(4)
    expect(egress.first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.2/32' })
    expect(egress.first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.4/32' })
    expect(egress.first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.5/32' })
    expect(egress.first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.6/32' })
    expect(egress.first['ports'].size).to eq(1)
    expect(egress.first['ports']).to include('protocol' => 'TCP', 'port' => 3306)
  end

  it 'db with supported requirements' do
    factory = eval_stacks do
      stack 'db_supported_reqs' do
        mysql_cluster 'exampledb' do
          self.role_in_name = false
          self.database_name = 'exampledb'
          self.master_instances = 1
          self.slave_instances = 2
          self.include_master_in_read_only_cluster = false
          self.supported_requirements = {
            :master => %w(e-exampledb-001.earth.net.local)
          }
        end
        app_service 'myapp', :kubernetes => true do
          self.groups = ['blue']
          self.application = 'rw-app'
          self.use_ha_mysql_ordering = true
          depend_on 'exampledb', environment.name, :master
        end
      end
      env 'e', :primary_site => 'earth' do
        instantiate_stack 'db_supported_reqs'
      end
    end

    machine_sets = factory.inventory.find_environment('e').definitions['db_supported_reqs'].k8s_machinesets
    k8s = machine_sets['myapp'].to_k8s(app_deployer, dns_resolver, hiera_provider)

    network_policies = k8s.resources.select do |policy|
      policy['kind'] == "NetworkPolicy"
    end

    expect(network_policies.size).to eq(2)
    expect(network_policies[1]['metadata']['name']).to eql('allow-myapp-out-to-e-exampledb-3306')
    egress = network_policies[1]['spec']['egress']
    expect(egress.size).to eq(1)
    expect(egress.first['to'].size).to eq(1)
    expect(egress.first['to']).to include('ipBlock' => { 'cidr' => '3.1.4.2/32' })
  end

  it 'raises error when supported requirements enabled but requirement not specified' do
    factory = eval_stacks do
      stack 'db_supported_reqs' do
        mysql_cluster 'exampledb' do
          self.role_in_name = false
          self.database_name = 'exampledb'
          self.master_instances = 1
          self.slave_instances = 2
          self.include_master_in_read_only_cluster = false
          self.supported_requirements = {
            :master => %w(e-exampledb-001.earth.net.local)
          }
        end
        app_service 'myapp', :kubernetes => true do
          self.groups = ['blue']
          self.application = 'rw-app'
          self.use_ha_mysql_ordering = true
          depend_on 'exampledb', environment.name
        end
      end
      env 'e', :primary_site => 'earth' do
        instantiate_stack 'db_supported_reqs'
      end
    end

    machine_sets = factory.inventory.find_environment('e').definitions['db_supported_reqs'].k8s_machinesets
    expect { machine_sets['myapp'].to_k8s(app_deployer, dns_resolver, hiera_provider) }.
      to raise_error(RuntimeError, match(/must declare its requirement on/))
  end
end
