require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack 'loadbalancer' do
      loadbalancer
    end
    stack 'example' do
      virtual_appserver 'exampleapp2' do
        self.groups = ['blue']
        self.application = 'example2'
        if 'e1' == environment.name
          depend_on('exampledb', 'e1')
        elsif 'pg' == environment.name
          depend_on('exampledb', 'pg')
        else
          depend_on('exampledb', 'e1')
        end
      end
    end

    stack 'example_db' do
      mysql_cluster 'exampledb' do
        self.database_name = 'example'
        self.backup_instances = 1
        self.slave_instances = 2
        self.secondary_site_slave_instances = 1
        self.include_master_in_read_only_cluster = false
      end
    end

    env 'e1', :primary_site => 'space', :secondary_site => 'earth' do
      env 'pg', :production => true do
        instantiate_stack 'example_db'
        instantiate_stack 'example'
      end

      instantiate_stack 'example_db'
      instantiate_stack 'example'
    end

    env 'e2', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'loadbalancer'
      instantiate_stack 'example'
    end

    stack 'example_db_depended_on_in_different_ways' do
      mysql_cluster 'dependedondb' do
        self.database_name = 'dependedondb'
        self.master_instances = 2
        self.slave_instances = 3
        self.secondary_site_slave_instances = 1
        self.include_master_in_read_only_cluster = false
        self.supported_dependencies = [:active_master, :read_only, :read_only_bulkhead]
      end
    end

    stack 'read_write_example' do
      virtual_appserver 'rwapp' do
        self.groups = ['blue']
        self.application = 'rw-app'
        depend_on_with_requirement 'dependedondb', environment.name, [:active_master]
      end
    end

    stack 'read_only_example' do
      virtual_appserver 'roapp' do
        self.groups = ['blue']
        self.application = 'ro-app'
        depend_on_with_requirement 'dependedondb', environment.name, [:read_only]
      end
    end

    stack 'read_only_bulkhead_example' do
      virtual_appserver 'robulkheadapp' do
        self.groups = ['blue']
        self.application = 'ro-bulkhead-app'
        depend_on_with_requirement 'dependedondb', environment.name, [:read_only_bulkhead]
      end
    end

    stack 'read_only_second_site_cluster' do
      virtual_appserver 'rosecondaryapp' do
        self.groups = ['blue']
        self.application = 'ro-secondary-app'
        depend_on_with_requirement 'dependedondb', environment.name, [:read_only]
      end
    end

    env 'e3', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example_db_depended_on_in_different_ways'
      instantiate_stack 'read_write_example'
      instantiate_stack 'read_only_example'
      instantiate_stack 'read_only_bulkhead_example'
      instantiate_stack 'read_only_second_site_cluster'
    end
  end

  host('e2-exampleapp2-002.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['db.example.database']).to eql('example')
    expect(deps['db.example.hostname']).to eql('e1-exampledb-001.space.net.local')
    expect(deps['db.example.port']).to eql('3306')
    expect(deps['db.example.password_hiera_key']).to eql('enc/e2/example2/mysql_password')
    expect(deps['db.example.username']).to eql('example2')
    expect(deps['db.example.read_only_cluster']).to eql(
      'e1-exampledb-001.earth.net.local' \
    )
  end

  host('e1-exampleapp2-002.mgmt.space.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.example.database']).to eql('example')
    expect(deps['db.example.hostname']).to eql('e1-exampledb-001.space.net.local')
    expect(deps['db.example.port']).to eql('3306')
    expect(deps['db.example.password_hiera_key']).to eql('enc/e1/example2/mysql_password')
    expect(deps['db.example.username']).to eql('example2')
    expect(deps['db.example.read_only_cluster']).to eql(
      'e1-exampledb-002.space.net.local,e1-exampledb-003.space.net.local' \
    )
  end

  host('pg-exampleapp2-002.mgmt.space.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.example.database']).to eql('example')
    expect(deps['db.example.hostname']).to eql('pg-exampledb-001.space.net.local')
    expect(deps['db.example.port']).to eql('3306')
    expect(deps['db.example.password_hiera_key']).to eql('enc/pg/example2/mysql_password')
    expect(deps['db.example.username']).to eql('example2')
    expect(deps['db.example.read_only_cluster']).to eql(
      'pg-exampledb-002.space.net.local,pg-exampledb-003.space.net.local' \
    )
  end

  host('e3-rwapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.dependedondb.hostname']).to eql('e3-dependedondb-001.earth.net.local')
  end

  # Following tests are Work-in-progress for specifying a mysql db to depend on
  #  -- gallan, 2015-10-20
  xhost('e3-roapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.dependedondb.read_only_cluster']).to eql(
      'e3-dependedondb-003.earth.net.local,e3-dependedondb-004.earth.net.local'
    )
  end

  xhost('e3-robulkheadapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.dependedondb.read_only_cluster']).to eql('e3-dependedondb-005.earth.net.local')
  end

  xhost('e3-rosecondaryapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.dependedondb.hostname']).to eql('e3-dependedondb-001.space.net.local')
  end
end
