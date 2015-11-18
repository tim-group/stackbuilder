require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'should provide a single instance mode to be backwards compatible with old mysqldb code' do
  given do
    stack "mysql" do
      mysql_cluster "frdb" do
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
      mysql_cluster "frdb"
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
      mysql_cluster "frdb"
    end

    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end

  host("testing-frdb-001.mgmt.space.net.local") do |host|
    expect(host.master?).to eql true
    expect(host.backup?).to eql false
    expect(host.to_enc['role::mysql_server']['dependant_instances']).to eql([
      'testing-frdb-002.space.net.local',
      'testing-frdbbackup-001.earth.net.local'
    ])
  end
  host("testing-frdb-002.mgmt.space.net.local") do |host|
    expect(host.master?).to eql false
    expect(host.backup?).to eql false
  end
  host("testing-frdbbackup-001.mgmt.earth.net.local") do |host|
    expect(host.master?).to eql false
    expect(host.backup?).to eql true
    expect(host.to_specs.shift[:storage][:"/mnt/storage"][:size]).to eql '10G'
  end
end

describe_stack 'should default to disallow destory' do
  given do
    stack "mysql" do
      mysql_cluster "spoondb"
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
        each_machine(&:allow_destroy)
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
        each_machine(&:allow_destroy)
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['backup']).to eql(false)
    expect(enc_server_role['database_name']).to eql('mydb')
    expect(enc_server_role['datadir']).to eql('/mnt/data/mysql')
    expect(enc_server_role['environment']).to eql('testing')
    expect(enc_server_role['master']).to eql(true)

    enc_rights = host.to_enc['role::mysql_multiple_rights']['rights']
    expect(enc_rights['mydb']['environment']).to eql('testing')
    expect(enc_rights['mydb']['database_name']).to eql('mydb')

    expect(host.to_enc).to include('server::default_new_mgmt_net_local')
    expect(host.to_enc['mysql_hacks::replication_rights_wrapper']['rights']).to eql(
      'replicant@testing-mydb-002.space.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      },
      'replicant@testing-mydbbackup-001.earth.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      }
    )
  end
  host("testing-mydb-002.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['backup']).to eql(false)
    expect(enc_server_role['database_name']).to eql('mydb')
    expect(enc_server_role['datadir']).to eql('/mnt/data/mysql')
    expect(enc_server_role['environment']).to eql('testing')
    expect(enc_server_role['master']).to eql(false)

    enc_rights = host.to_enc['role::mysql_multiple_rights']['rights']
    expect(enc_rights['mydb']['environment']).to eql('testing')
    expect(enc_rights['mydb']['database_name']).to eql('mydb')

    expect(host.to_enc).to include('server::default_new_mgmt_net_local')
    expect(host.to_enc).to include('mysql_hacks::replication_rights_wrapper')
    expect(host.to_enc).to include('server::default_new_mgmt_net_local')

    expect(host.to_enc['mysql_hacks::replication_rights_wrapper']['rights']).to eql(
      'replicant@testing-mydb-001.space.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      },
      'replicant@testing-mydbbackup-001.earth.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      }
    )
  end
  host("testing-mydbbackup-001.mgmt.earth.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    expect(enc_server_role['backup']).to eql(true)
    expect(enc_server_role['database_name']).to eql('mydb')
    expect(enc_server_role['datadir']).to eql('/mnt/data/mysql')
    expect(enc_server_role['environment']).to eql('testing')
    expect(enc_server_role['master']).to eql(false)

    expect(host.to_enc['mysql_hacks::replication_rights_wrapper']['rights']).to eql(
      'replicant@testing-mydb-001.space.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      },
      'replicant@testing-mydb-002.space.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      }
    )
    expect(host.to_enc).to include('server::default_new_mgmt_net_local')
    expect(host.to_enc).to include('mysql_hacks::replication_rights_wrapper')
    expect(host.to_enc).not_to include('mysql_hacks::application_rights_wrapper')
  end
end
describe_stack 'should provide the correct application rights' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = "ref"
      end
    end
    stack "app_server" do
      virtual_appserver "applong" do
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
      eql('enc/testing/SuperLongLengthName/mysql_password')
  end
  host("testing-applong-001.mgmt.space.net.local") do |host|
    rights = host.to_enc['role::http_app']['dependencies']
    expect(rights['db.ref.database']).to eql('ref')
    expect(rights['db.ref.driver']).to eql('com.mysql.jdbc.Driver')
    expect(rights['db.ref.hostname']).to eql('testing-mydb-001.space.net.local')
    expect(rights['db.ref.port']).to eql('3306')
    expect(rights['db.ref.password_hiera_key']).to eql('enc/testing/SuperLongLengthName/mysql_password')
    expect(rights['db.ref.username']).to eql('SuperLongLengthN')
  end
end

describe_stack 'should allow storage options to be overwritten' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = "mydb"
        data_size('14G')
        backup_size('29G')
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

describe_stack 'should have mysql 5.1.49-1ubuntu8 as the default version of mysql' do
  given do
    stack "mysql51" do
      mysql_cluster "my51" do
      end
    end
    stack "mysql55" do
      mysql_cluster "my55" do
        each_machine { |machine| machine.version = '5.5.43-0ubuntu0.12.04.1' }
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql51"
      instantiate_stack "mysql55"
    end
  end
  host("testing-my51-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['version']).to eql('5.1.49-1ubuntu8')
  end
  host("testing-my55-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['version']).to eql('5.5.43-0ubuntu0.12.04.1')
  end
end

describe_stack 'should support dependencies' do
  given do
    stack 'fr' do
      virtual_appserver 'frapp' do
        self.application = 'futuresroll'
        depend_on 'frdb'
      end
    end
    stack 'fr_db' do
      mysql_cluster 'frdb' do
        self.database_name = "futuresroll"
      end
    end
    stack 'hr' do
      virtual_appserver 'hrapp' do
        self.application = 'huturesroll'
      end
    end
    stack 'hr_db' do
      mysql_cluster 'hrdb' do
        self.database_name = "huturesroll"
      end
    end

    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "fr"
      instantiate_stack "fr_db"
      instantiate_stack "hr"
      instantiate_stack "hr_db"
    end
  end
  host("testing-frdb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['dependant_instances'].size).to eql(4)
    expect(host.to_enc['role::mysql_server']['dependant_instances']).to \
      include('testing-frapp-001.space.net.local', 'testing-frapp-002.space.net.local')
    expect(host.to_enc['role::mysql_server']['dependant_instances']).to \
      include('testing-frdb-002.space.net.local', 'testing-frdbbackup-001.earth.net.local')
    expect(host.to_enc['role::mysql_server']['dependencies']).to eql({})
  end
  host("testing-hrdb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::mysql_server']['dependant_instances'].size).to eql(2)
    expect(host.to_enc['role::mysql_server']['dependant_instances']).to \
      include('testing-hrdb-002.space.net.local', 'testing-hrdbbackup-001.earth.net.local')
    expect(host.to_enc['role::mysql_server']['dependencies']).to eql({})
  end
end

describe_stack 'should provide the correct server_ids' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
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
  host("testing-mydb-002.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::stacks_mysql_config')).to eql(false)
  end
end

describe_stack 'should allow custom mysql_config to be specified' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
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

describe_stack 'should allow percona_checksum_tools flag to be specified' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = 'test'
        self.enable_percona_checksum_tools = true
        self.percona_checksum_ignore_tables = 'test.ignore'
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
    expect(pct['ignore_tables']).to eql('test.ignore')
  end
end

describe_stack 'should provide the correct monitoring checks for master and slave' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = 'test'
        self.master_instances = 1
        self.slave_instances = 1
        self.backup_instances = 1
        self.secondary_site_slave_instances = 1
      end
    end
    env "production", :production => true, :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("production-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to eql(%w(heartbeat))
  end
  host("production-mydb-002.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to eql(%w(replication_running replication_delay))
  end
  host("production-mydb-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to eql(%w(replication_running replication_delay))
  end
  host("production-mydbbackup-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_server')).to eql(true)
    enc = host.to_enc['role::mysql_server']
    expect(enc['monitoring_checks']).to eql(%w(replication_running replication_delay))
  end
end

describe_stack 'should allow creation of user_access_servers in primary_site' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
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
    expect(host.to_enc.key?('role::mysql_multiple_rights')).to eql(false)
  end
  host("production-mydbuseraccess-001.mgmt.space.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_multiple_rights')).to eql(true)
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
    expect(host.to_enc.key?('role::mysql_multiple_rights')).to eql(false)
  end
  host("production-mydbuseraccess-001.mgmt.earth.net.local") do |host|
    expect(host.to_enc.key?('role::mysql_multiple_rights')).to eql(true)
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
    expect(host.to_enc.key?('role::mysql_multiple_rights')).to eql(true)
  end
  it_stack 'should contain all the expected hosts' do |stack|
    expect(stack).to have_hosts([
      'production-mydb-001.mgmt.space.net.local'
    ])
  end
end
