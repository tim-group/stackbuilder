require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

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
          )
        }
      end
    end

    stack 'example_legacy_db' do
      legacy_mysql_cluster 'examplelegacydb' do
        self.instances = 1
        self.database_name = 'examplelegacydb'
        self.application = 'examplelegacy'
      end
    end

    stack 'master_with_slaves_example' do
      app_service 'myapp' do
        self.groups = ['blue']
        self.application = 'rw-app'
        depend_on 'exampledb', environment.name, :master_with_slaves
        depend_on 'examplelegacydb', environment.name, :read_only

        each_machine do |machine|
          machine.enc_hack do |enc|
            cluster = enc["role::http_app"]["dependencies"]["db.exampledb.read_only_cluster"]
            slaves = cluster.split(",")

            if machine.mgmt_fqdn.include?("002")
              enc["role::http_app"]["dependencies"]["db.exampledb.read_only_cluster"] = slaves.reverse.join(",")
            end
            enc
          end
        end
      end
    end

    env 'e', :primary_site => 'earth', :secondary_site => 'space' do
      instantiate_stack 'example_db_depended_on_in_different_ways'
      instantiate_stack 'example_legacy_db'
      instantiate_stack 'master_with_slaves_example'
    end
  end

  host('e-myapp-001.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.hostname']).to eql('e-exampledb-001.earth.net.local')
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-003.earth.net.local,e-exampledb-004.earth.net.local")
    expect(deps['db.examplelegacydb.hostname']).to eql('e-examplelegacydb-001.earth.net.local')
    expect(deps['db.examplelegacydb.read_only_cluster']).to eql("e-examplelegacydb-001.earth.net.local")
  end

  host('e-myapp-002.mgmt.earth.net.local') do |host|
    deps = host.to_enc['role::http_app']['dependencies']

    expect(deps['db.exampledb.hostname']).to eql('e-exampledb-001.earth.net.local')
    expect(deps['db.exampledb.read_only_cluster']).to eql("e-exampledb-004.earth.net.local,e-exampledb-003.earth.net.local")
    expect(deps['db.examplelegacydb.hostname']).to eql('e-examplelegacydb-001.earth.net.local')
    expect(deps['db.examplelegacydb.read_only_cluster']).to eql("e-examplelegacydb-001.earth.net.local")
  end
end
