require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'should provide a single instance mode to be backwards compatible with old mysqldb code' do
  given do
    stack "mysql" do
      mysql_cluster "frdb" do
        self.role_in_name = false
        single_instance
      end
    end

    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end

  host("testing-frdb-001.mgmt.space.net.local") do |host|
    expect(host.master?).to eql true
    expect(host.to_enc['role::mysql_server']['dependant_instances']).to eql nil
  end
end
describe_stack 'should provide the correct cross routing enc data' do
  given do
    stack "mysql" do
      mysql_cluster "frdb" do
        self.role_in_name = false
      end
    end

    env "testing", :primary_site => "pg", :secondary_site => "oy" do
      instantiate_stack "mysql"
    end
  end

  host("testing-frdb-001.mgmt.pg.net.local") do |host|
    expect(host.to_enc['networking::routing::to_site']).to eql('network' => 'prod',
                                                               'site'    => 'oy')
  end
  host("testing-frdb-002.mgmt.pg.net.local") do |host|
    expect(host.to_enc['networking::routing::to_site']).to eql('network' => 'prod',
                                                               'site'    => 'oy')
  end
  host("testing-frdbbackup-001.mgmt.oy.net.local") do |host|
    expect(host.to_enc['networking::routing::to_site']).to eql('network' => 'prod',
                                                               'site'    => 'pg')
  end
end

describe_stack 'should provide 3 mysql servers by default, one is a master' do
  given do
    stack "mysql" do
      mysql_cluster "frdb" do
        self.role_in_name = false
      end
    end

    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end

  host("testing-frdb-001.mgmt.space.net.local") do |host|
    expect(host.role).to eql(:master)
  end
  host("testing-frdb-002.mgmt.space.net.local") do |host|
    expect(host.role).to eql(:slave)
  end
  host("testing-frdbbackup-001.mgmt.earth.net.local") do |host|
    expect(host.role).to eql(:backup)
    expect(host.to_specs.shift[:storage][:"/mnt/storage"][:size]).to eql '10G'
  end
end

describe_stack 'should default to disallow destory' do
  given do
    stack "mysql" do
      mysql_cluster "spoondb" do
        self.role_in_name = false
      end
    end

    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end

  host("testing-spoondb-001.mgmt.space.net.local") do |host|
    expect(host.destroyable?).to eql false
    expect(host.to_specs.shift[:disallow_destroy]).to eql true
  end
end

describe_stack 'should allow destroy to be overwritten' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        each_machine { |machine| machine.destroyable = true }
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.destroyable?).to eql true
    expect(host.to_specs.shift[:disallow_destroy]).to eql nil
  end
end

describe_stack 'should provide correct enc data' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = "mydb"
        self.role_in_name = false
        each_machine { |machine| machine.destroyable = true }
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['role']).to eql(:master)
    expect(enc_server_role['database_name']).to eql('mydb')
    expect(enc_server_role['datadir']).to eql('/mnt/data/mysql')
    expect(enc_server_role['environment']).to eql('testing')

    enc_rights = host.to_enc['role::mysql_multiple_rights']['rights']
    expect(enc_rights['mydb']['environment']).to eql('testing')
    expect(enc_rights['mydb']['database_name']).to eql('mydb')

    expect(host.to_enc).to include('server')
    expect(host.to_enc['mysql_hacks::replication_rights_wrapper']['rights']).to eql(
      'replicant@testing-mydb-002.space.net.local' => {
        'password_hiera_key' => 'testing/mydb/replication/mysql_password'
      },
      'replicant@testing-mydbbackup-001.earth.net.local' => {
        'password_hiera_key' => 'testing/mydb/replication/mysql_password'
      }
    )
  end
  host("testing-mydb-002.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['role']).to eql(:slave)
    expect(enc_server_role['database_name']).to eql('mydb')
    expect(enc_server_role['datadir']).to eql('/mnt/data/mysql')
    expect(enc_server_role['environment']).to eql('testing')

    enc_rights = host.to_enc['role::mysql_multiple_rights']['rights']
    expect(enc_rights['mydb']['environment']).to eql('testing')
    expect(enc_rights['mydb']['database_name']).to eql('mydb')

    expect(host.to_enc).to include('server')
    expect(host.to_enc).to include('mysql_hacks::replication_rights_wrapper')
    expect(host.to_enc).to include('server')

    expect(host.to_enc['mysql_hacks::replication_rights_wrapper']['rights']).to eql(
      'replicant@testing-mydb-001.space.net.local' => {
        'password_hiera_key' => 'testing/mydb/replication/mysql_password'
      },
      'replicant@testing-mydbbackup-001.earth.net.local' => {
        'password_hiera_key' => 'testing/mydb/replication/mysql_password'
      }
    )
  end
  host("testing-mydbbackup-001.mgmt.earth.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['role']).to eql(:backup)
    expect(enc_server_role['database_name']).to eql('mydb')
    expect(enc_server_role['datadir']).to eql('/mnt/data/mysql')
    expect(enc_server_role['environment']).to eql('testing')

    expect(host.to_enc['mysql_hacks::replication_rights_wrapper']['rights']).to eql(
      'replicant@testing-mydb-001.space.net.local' => {
        'password_hiera_key' => 'testing/mydb/replication/mysql_password'
      },
      'replicant@testing-mydb-002.space.net.local' => {
        'password_hiera_key' => 'testing/mydb/replication/mysql_password'
      }
    )
    expect(host.to_enc).to include('server')
    expect(host.to_enc).to include('mysql_hacks::replication_rights_wrapper')
    expect(host.to_enc).not_to include('mysql_hacks::application_rights_wrapper')
  end
end
describe_stack 'should provide the correct application rights' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = "ref"
      end
    end
    stack "app_server" do
      app_service "applong" do
        self.application = "SuperLongLengthName"
        depend_on 'mydb'
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
      instantiate_stack "app_server"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    rights = host.to_enc['mysql_hacks::application_rights_wrapper']['rights']
    expect(rights['SuperLongLengthN@testing-applong-001.space.net.local/ref']['password_hiera_key']).to \
      eql('testing/SuperLongLengthName/mysql_password')
    expect(rights['SuperLongLengthN@testing-applong-001.space.net.local/ref']['passwords_hiera_key']).to \
      eql('testing/SuperLongLengthName/mysql_passwords')
  end
  host("testing-applong-001.mgmt.space.net.local") do |host|
    rights = host.to_enc['role::http_app']['dependencies']
    expect(rights['db.ref.database']).to eql('ref')
    expect(rights['db.ref.driver']).to eql('com.mysql.jdbc.Driver')
    expect(rights['db.ref.hostname']).to eql('testing-mydb-001.space.net.local')
    expect(rights['db.ref.port']).to eql('3306')
    expect(rights['db.ref.password_hiera_key']).to eql('testing/SuperLongLengthName/mysql_password')
    expect(rights['db.ref.username']).to eql('SuperLongLengthN')
  end
end

describe_stack 'should provide the correct application rights if the app server is in kubernetes' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = "ref"
      end
    end
    stack "app_server" do
      app_service "applong", :kubernetes => true do
        self.application = "SuperLongLengthName"
        depend_on 'mydb'
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
      instantiate_stack "app_server"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    rights = host.to_enc['mysql_hacks::application_rights_wrapper']['rights']
    expect(rights['SuperLongLengthN@space-testing-applong/ref']['password_hiera_key']).to \
      eql('testing/SuperLongLengthName/mysql_password')
    expect(rights['SuperLongLengthN@space-testing-applong/ref']['passwords_hiera_key']).to \
      eql('testing/SuperLongLengthName/mysql_passwords')
    expect(rights['SuperLongLengthN@space-testing-applong/ref']['allow_kubernetes']).to be(true)
    expect(rights['SuperLongLengthN@space-testing-applong/ref']['kubernetes_clusters']).to eql(['space'])
  end
end

describe_stack 'should allow storage options to be overwritten' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = "mydb"
        each_machine do |machine|
          machine.modify_storage('/mnt/data'   => { :size => '14G' })
          machine.modify_storage('/mnt/storage' => { :size => '29G' }) if machine.role_of?(:backup)
        end
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:type]).to eql "data"
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:size]).to eql "14G"
    expect(host.to_specs.shift[:storage]['/tmp'.to_sym][:type]).to eql "os"
    expect(host.to_specs.shift[:storage]['/tmp'.to_sym][:size]).to eql "10G"
  end
  host("testing-mydbbackup-001.mgmt.earth.net.local") do |host|
    expect(host.to_specs.shift[:storage]['/mnt/storage'.to_sym][:size]).to eql "29G"
  end
end

describe_stack 'should allow backup_instance_site to be specified' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.backup_instance_site = :primary_site
        self.master_instances = 1
        self.slave_instances = 0
        self.backup_instances = 1
        self.secondary_site_slave_instances = 0
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'testing-mydb-001.mgmt.space.net.local',
      'testing-mydbbackup-001.mgmt.space.net.local'
    ])
  end
end

describe_stack 'should always provide a default data mount of /mnt/data with sensible defaults' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:type]).to eql "data"
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:persistent]).to eql true
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:size]).to eql '10G'
  end
end

describe_stack 'should provide a default of 4GB of ram and 2 cpu cores' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.shift[:ram]).to eql '4194304'
    expect(host.to_specs.shift[:vcpus]).to eql '2'
  end
end

describe_stack 'should have mysql 5.6.25-1ubuntu12.04 as the default version of mysql on precise' do
  given do
    stack "mysql51" do
      mysql_cluster "my51" do
        self.role_in_name = false
        each_machine do |machine|
          machine.template(:precise)
        end
      end
    end
    stack "mysql55" do
      mysql_cluster "my55" do
        self.role_in_name = false
        each_machine do |machine|
          machine.template(:precise)
          machine.version = '5.5.43-0'
        end
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql51"
      instantiate_stack "mysql55"
    end
  end
  host("testing-my51-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['version']).to eql('5.6.25-1ubuntu12.04')
  end
  host("testing-my55-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['version']).to eql('5.5.43-0ubuntu12.04')
  end
end

describe_stack 'should have mysql 5.6.25-1ubuntu14.04 as the default version of mysql on trusty' do
  given do
    stack "mysql51" do
      mysql_cluster "my51" do
        self.role_in_name = false
        each_machine do |machine|
          machine.template(:trusty)
        end
      end
    end
    stack "mysql55" do
      mysql_cluster "my55" do
        self.role_in_name = false
        each_machine do |machine|
          machine.version = '5.5.43-0'
          machine.template(:trusty)
        end
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql51"
      instantiate_stack "mysql55"
    end
  end
  host("testing-my51-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['version']).to eql('5.6.25-1ubuntu14.04')
  end
  host("testing-my55-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['version']).to eql('5.5.43-0ubuntu14.04')
  end
end

describe_stack 'should not alter legacy server_ids' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.master_instances = 1
        self.slave_instances = 1
        self.backup_instances = 1
        self.secondary_site_slave_instances = 2
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(1)
  end
  host("testing-mydb-002.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(2)
  end
  host("testing-mydb-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(101)
  end
  host("testing-mydbbackup-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(201)
  end
end
describe_stack 'should allow server_id to be overwritten' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        each_machine { |machine| machine.server_id = 99 }
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['server_id']).to eql(99)
  end
end

describe_stack 'should provide the correct server_ids' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = true
        self.master_instances = 1
        self.slave_instances = 1
        self.backup_instances = 1
        self.primary_site_backup_instances = 1
        self.secondary_site_slave_instances = 1
        self.secondary_site_user_access_instances = 1
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'testing-mydb-master-001.mgmt.space.net.local',
      'testing-mydb-slave-001.mgmt.space.net.local',
      'testing-mydb-slave-001.mgmt.earth.net.local',
      'testing-mydb-backup-001.mgmt.space.net.local',
      'testing-mydb-backup-001.mgmt.earth.net.local',
      'testing-mydb-useraccess-001.mgmt.earth.net.local'
    ])
  end
  host("testing-mydb-master-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(1)
  end
  host("testing-mydb-slave-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(101)
  end
  host("testing-mydb-slave-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(151)
  end
  host("testing-mydb-backup-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(201)
  end
  host("testing-mydb-backup-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(251)
  end
  host("testing-mydb-useraccess-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['server_id']).to eql(351)
  end
end

describe_stack 'should allow server_id to be overwritten' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        each_machine { |machine| machine.server_id = 99 }
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['server_id']).to eql(99)
  end
end

describe_stack 'should allow server_id_offset to be specified' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.master_instances = 1
        self.slave_instances = 0
        self.backup_instances = 0
        self.secondary_site_slave_instances = 0
        @master_index_offset = 2
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(['testing-mydb-003.mgmt.space.net.local'])
  end
end

describe_stack 'should allow index_offset' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        @server_id_offset = 1000
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['server_id']).to eql(1001)
  end
end

describe_stack 'should allow use_gtids to be specified' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        each_machine do |machine|
          machine.use_gtids = true if %w(testing-mydb-001).include? machine.hostname
        end
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    stacks_mysql_config = host.to_enc['role::stacks_mysql_config']
    expect(stacks_mysql_config['config']['mysqld']['gtid_mode']).to eql('ON')
    expect(stacks_mysql_config['config']['mysqld']['enforce_gtid_consistency']).to eql('ON')
  end
end

describe_stack 'should provide a default mysql config' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'magic'
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    stacks_mysql_config = host.to_enc['role::stacks_mysql_config']
    expect(stacks_mysql_config['config']['mysqld']['replicate-do-db'].size).to eql(2)
    expect(stacks_mysql_config['config']['mysqld']['replicate-do-db']).to include('percona', 'magic')
  end
end

describe_stack 'should allow custom mysql_config to be specified' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        each_machine do |machine|
          machine.config = {
            'mysqld' => {
              'innodb_buffer_pool_size' => '10G',
              'innodb_buffer_pool_instances' => '10'
            }
          }
        end
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
    env "latest", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    stacks_mysql_config = host.to_enc['role::stacks_mysql_config']
    expect(stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_size']).to eql('10G')
    expect(stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_instances']).to eql('10')
    expect(stacks_mysql_config['restart_mysql']).to eql(false)
  end
  host("latest-mydb-002.mgmt.space.net.local") do |host|
    stacks_mysql_config = host.to_enc['role::stacks_mysql_config']
    expect(stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_size']).to eql('10G')
    expect(stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_instances']).to eql('10')
    expect(stacks_mysql_config['restart_mysql']).to eql(true)
  end
end

describe_stack 'should merge mysql_config with gtid_config when using use_gtids' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        each_machine do |machine|
          machine.use_gtids = true
          machine.config = {
            'mysqld' => {
              'innodb_buffer_pool_size' => '10G'
            }
          }
        end
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
    env "latest", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    stacks_mysql_config = host.to_enc['role::stacks_mysql_config']
    expect(stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_size']).to eql('10G')
    expect(stacks_mysql_config['config']['mysqld']['gtid_mode']).to eql('ON')
    expect(stacks_mysql_config['config']['mysqld']['enforce_gtid_consistency']).to eql('ON')
  end
end

describe_stack 'should create secondary_sited slave databases' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.master_instances = 1
        self.slave_instances = 1
        self.backup_instances = 1
        self.secondary_site_slave_instances = 2
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'production-mydb-001.mgmt.space.net.local',
        'production-mydb-002.mgmt.space.net.local',
        'production-mydbbackup-001.mgmt.earth.net.local',
        'production-mydb-001.mgmt.earth.net.local',
        'production-mydb-002.mgmt.earth.net.local'
      ]
    )
  end
end

describe_stack 'should allow percona_checksum flag to be specified' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.percona_checksum_ignore_tables = ['test.ignore']
        self.percona_checksum_monitoring = true
        self.master_instances = 1
        self.slave_instances = 1
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('percona::checksum_tools')).to eql(true)
    pct = host.to_enc['percona::checksum_tools']
    expect(pct['database_name']).to eql('test')
    expect(pct['master_fqdns']).to eql(['production-mydb-001.space.net.local'])
    expect(pct['ignore_tables']).to eql('test.heartbeat,test.ignore')
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    role = host.to_enc['role::mysql_server']
    expect(role['monitoring_checks']).to include('checksum')
  end
  host("production-mydb-002.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    role = host.to_enc['role::mysql_server']
    expect(role['monitoring_checks']).to include('checksum')
  end
end

describe_stack 'should allow percona_checksum flag to be specified' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.percona_checksum = false
        self.master_instances = 1
        self.slave_instances = 1
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('percona::checksum_tools')).to eql(false)
  end
end

describe_stack 'should provide the correct monitoring checks for master and slave' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 1
        self.slave_instances = 1
        self.backup_instances = 1
        self.secondary_site_slave_instances = 1
        self.percona_checksum_monitoring = true
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to eql(%w(heartbeat checksum))
  end
  host("production-mydb-002.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to eql(%w(replication_running replication_delay checksum))
  end
  host("production-mydb-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to eql(%w(replication_running replication_delay checksum))
  end
  host("production-mydbbackup-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to eql(%w(replication_running replication_delay checksum))
  end
end

describe_stack 'should provide replication checks for each master when there is more than one master in the cluster' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 2
        self.slave_instances = 0
        self.backup_instances = 0
        self.secondary_site_slave_instances = 0
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to include('replication_running', 'replication_delay')
  end
  host("production-mydb-002.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to include('replication_running', 'replication_delay')
  end
end

describe_stack 'should allow creation of user_access_servers in primary_site' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 1
        self.user_access_instances = 1
        self.slave_instances = 0
        self.backup_instances = 0
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_multiple_rights']['rights']['test']['create_read_only_users']).to be false
  end
  host("production-mydbuseraccess-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_multiple_rights']['rights']['test']['create_read_only_users']).to be true
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'production-mydb-001.mgmt.space.net.local',
      'production-mydbuseraccess-001.mgmt.space.net.local'
    ])
  end
end

describe_stack 'should allow creation of user_access_servers in secondary_site' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 1
        self.secondary_site_user_access_instances = 1
        self.slave_instances = 0
        self.backup_instances = 0
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_multiple_rights']['rights']['test']['create_read_only_users']).to be false
  end
  host("production-mydbuseraccess-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc['role::mysql_multiple_rights']['rights']['test']['create_read_only_users']).to be true
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'production-mydb-001.mgmt.space.net.local',
      'production-mydbuseraccess-001.mgmt.earth.net.local'
    ])
  end
end

describe_stack 'should grant_user_rights_by_default when no user_access_servers exist' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 1
        self.slave_instances = 0
        self.backup_instances = 0
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_multiple_rights']['rights']['test']['create_read_only_users']).to be(true)
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'production-mydb-001.mgmt.space.net.local'
    ])
  end
end

describe_stack 'should grant_user_rights_by_default when machine.grant_user_rights_by_default is set true' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 1
        self.user_access_instances = 1
        self.slave_instances = 0
        self.backup_instances = 0
        each_machine do |machine|
          machine.grant_user_rights_by_default = true if %w(production-mydb-001).include?(machine.hostname)
        end
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_multiple_rights']['rights']['test']['create_read_only_users']).to be(true)
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'production-mydb-001.mgmt.space.net.local',
      'production-mydbuseraccess-001.mgmt.space.net.local'
    ])
  end
end
describe_stack 'mysql servers must provide required params to role::mysql_server' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = 'test'
        self.master_instances = 1
        self.slave_instances = 1
        self.secondary_site_slave_instances = 1
        self.user_access_instances = 1
        self.secondary_site_user_access_instances = 1
        self.backup_instances = 1
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  all_hosts do |host|
    enc = host.to_enc
    expect(enc.key?('role::mysql_server')).to eql(true)
    role = enc['role::mysql_server']
    expect(role['backup']).to be_truthy.or be_falsey
    expect(role['database_name']).to be_an(String)
    expect(role['datadir']).to be_an(String)
    expect(role['master']).to be_truthy.or be_falsey
    expect(role['server_id']).to be_an(Integer)
    expect(role['charset']).to be_an(String)
    expect(role['version']).to be_an(String)
    expect(role['monitoring_checks']).to be_an(Array)
  end
end

describe_stack 'should not allow applications to depend_on user_access servers' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 1
        self.user_access_instances = 1
        self.slave_instances = 0
        self.backup_instances = 0
      end
    end
    stack "app_server" do
      app_service "app" do
        self.application = "app"
        depend_on 'mydb'
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
      instantiate_stack "app_server"
    end
  end
  host("production-app-001.mgmt.space.net.local") do |host|
    rights = host.to_enc['role::http_app']['dependencies']
    expect(rights['db.test.read_only_cluster']).to eql('production-mydb-001.space.net.local')
  end
  host("production-mydbuseraccess-001.mgmt.space.net.local") do |host|
    expect(host.to_enc).not_to include('mysql_hacks::application_rights_wrapper')
  end
end

describe_stack 'should not sort read only cluster servers when option false' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = 'test'
        self.master_instances = 1
        self.slave_instances = 1
        self.read_only_cluster_master_last = false
      end
    end
    stack "app_server" do
      app_service "app" do
        self.application = "app"
        depend_on 'mydb'
      end
    end
    env "production", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
      instantiate_stack "app_server"
    end
  end
  host("production-app-001.mgmt.space.net.local") do |host|
    rights = host.to_enc['role::http_app']['dependencies']
    expect(rights['db.test.read_only_cluster']).to eql('production-mydb-master-001.space.net.local,production-mydb-slave-001.space.net.local')
  end
end

describe_stack 'should by default provide read only cluster members in order slaves then master' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = 'test'
        self.master_instances = 1
        self.slave_instances = 1
      end
    end
    stack "app_server" do
      app_service "app" do
        self.application = "app"
        depend_on 'mydb'
      end
    end
    env "production", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
      instantiate_stack "app_server"
    end
  end
  host("production-app-001.mgmt.space.net.local") do |host|
    rights = host.to_enc['role::http_app']['dependencies']
    expect(rights['db.test.read_only_cluster']).to eql('production-mydb-slave-001.space.net.local,production-mydb-master-001.space.net.local')
  end
end

describe_stack 'should specify read only cluster members in order slaves then master when option set' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = 'test'
        self.master_instances = 1
        self.slave_instances = 1
        self.master_only_in_same_site = true
      end
    end
    stack "app_server" do
      app_service "app" do
        self.application = "app"
        depend_on 'mydb', 'production'
      end
    end
    env "latest", :primary_site => "earth", :secondary_site => "space" do
      instantiate_stack "app_server"
    end
    env "production", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("latest-app-001.mgmt.earth.net.local") do |host|
    rights = host.to_enc['role::http_app']['dependencies']
    expect(rights['db.test.hostname']).to eql('')
  end
end
describe_stack 'should create two masters' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 2
        self.user_access_instances = 0
        self.slave_instances = 0
        self.backup_instances = 0
      end
    end
    stack "app_server" do
      app_service "app" do
        self.application = "app"
        depend_on 'mydb'
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack 'app_server'
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['percona::checksum_tools']['master_fqdns']
    expect(enc).to eql(%w(production-mydb-001.space.net.local production-mydb-002.space.net.local))
  end
  host("production-mydb-002.mgmt.space.net.local") do |host|
    enc = host.to_enc['percona::checksum_tools']['master_fqdns']
    expect(enc).to eql(%w(production-mydb-001.space.net.local production-mydb-002.space.net.local))
  end
  host("production-app-001.mgmt.space.net.local") do |host|
    enc = host.to_enc
    expect(enc['role::http_app']['dependencies']['db.test.hostname']).to eql('production-mydb-001.space.net.local')
  end
end

describe_stack 'create primary site backup instances' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 1
        self.user_access_instances = 0
        self.slave_instances = 0
        self.backup_instances = 0
        self.primary_site_backup_instances = 1
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydbbackup-001.mgmt.space.net.local") do |host|
    enc = host.to_enc
    expect(enc).not_to be_nil
  end
end

describe_stack 'create standalone mysql servers' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.role_in_name = false
        self.database_name = 'test'
        self.master_instances = 0
        self.slave_instances = 0
        self.backup_instances = 0
        self.standalone_instances = 1
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to be_empty
    expect(enc['role']).to eql(:standalone)
  end
end

describe_stack 'should support instances as a site hash with roles' do
  given do
    stack 'mysql' do
      mysql_cluster "mydb" do
        self.master_instances = 1
        self.slave_instances = 1
        self.backup_instances = 1
        self.standalone_instances = 1
        self.user_access_instances = 1
      end
    end

    env "e1", :primary_site => "earth", :secondary_site => 'jupiter' do
      instantiate_stack "mysql"
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'e1-mydb-master-001.mgmt.earth.net.local',
        'e1-mydb-slave-001.mgmt.earth.net.local',
        'e1-mydb-standalone-001.mgmt.earth.net.local',
        'e1-mydb-backup-001.mgmt.jupiter.net.local',
        'e1-mydb-useraccess-001.mgmt.earth.net.local'
      ]
    )
  end
end

describe_stack 'should allow snapshot backups' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = 'test'
        self.master_instances = 1
        self.slave_instances = 0
        self.backup_instances = 1
        self.standalone_instances = 0
        self.snapshot_backups = true
        each_machine do |machine|
          next unless machine.role_of?(:backup)
          machine.snapshot_pv_size('60G')
          machine.snapshot_size = '256M'
          machine.snapshot_frequency_secs = 1800
          machine.snapshot_retention_secs = 1800 * 7
        end
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts(
      [
        'production-mydb-master-001.mgmt.space.net.local',
        'production-mydb-backup-001.mgmt.earth.net.local'
      ]
    )
  end
  host("production-mydb-master-001.mgmt.space.net.local") do |host|
    enc = host.to_enc
    expect(enc.key? 'db_snapshot').to be false
  end
  host("production-mydb-backup-001.mgmt.earth.net.local") do |host|
    enc = host.to_enc
    expect(enc.key? 'db_snapshot').to be true
    expect(enc['db_snapshot']['snapshot_size']).to eql '256M'
    expect(enc['db_snapshot']['snapshot_frequency_secs']).to eql 1800
    expect(enc['db_snapshot']['snapshot_retention_secs']).to eql 12_600

    spec = host.to_spec
    expect(spec[:storage][:"/mnt/data"][:prepare][:options][:create_guest_lvm]).to be true
    expect(spec[:storage][:"/mnt/data"][:prepare][:options][:guest_lvm_pv_size]).to eql '60G'
  end
end
