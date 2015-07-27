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
    host.master?.should eql true
    host.to_enc['role::mysql_server']['dependant_instances'].should eql nil
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
    host.to_enc['networking::routing::to_site'].should eql('network' => 'prod',
                                                           'site'    => 'oy')
  end
  host("testing-frdb-002.mgmt.pg.net.local") do |host|
    host.to_enc['networking::routing::to_site'].should eql('network' => 'prod',
                                                           'site'    => 'oy')
  end
  host("testing-frdbbackup-001.mgmt.oy.net.local") do |host|
    host.to_enc['networking::routing::to_site'].should eql('network' => 'prod',
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
    host.master?.should eql true
    host.backup?.should eql false
    host.to_enc['role::mysql_server']['dependant_instances'].should eql([
      'testing-frdb-002.space.net.local',
      'testing-frdbbackup-001.earth.net.local'
    ])
  end
  host("testing-frdb-002.mgmt.space.net.local") do |host|
    host.master?.should eql false
    host.backup?.should eql false
  end
  host("testing-frdbbackup-001.mgmt.earth.net.local") do |host|
    host.master?.should eql false
    host.backup?.should eql true
    host.to_specs.shift[:storage][:"/mnt/storage"][:size].should eql '10G'
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
    host.destroyable?.should eql false
    host.to_specs.shift[:disallow_destroy].should eql true
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
    host.destroyable?.should eql true
    host.to_specs.shift[:disallow_destroy].should eql nil
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
    enc_server_role['backup'].should eql(false)
    enc_server_role['database_name'].should eql('mydb')
    enc_server_role['datadir'].should eql('/mnt/data/mysql')
    enc_server_role['environment'].should eql('testing')
    enc_server_role['master'].should eql(true)
    enc_server_role['server_id'].should eql(1)

    enc_rights = host.to_enc['role::mysql_multiple_rights']['rights']
    enc_rights['mydb']['environment'].should eql('testing')
    enc_rights['mydb']['database_name'].should eql('mydb')

    host.to_enc.should include('server::default_new_mgmt_net_local')
    host.to_enc['mysql_hacks::replication_rights_wrapper']['rights'].should eql(
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
    enc_server_role['backup'].should eql(false)
    enc_server_role['database_name'].should eql('mydb')
    enc_server_role['datadir'].should eql('/mnt/data/mysql')
    enc_server_role['environment'].should eql('testing')
    enc_server_role['master'].should eql(false)
    enc_server_role['server_id'].should eql(2)

    enc_rights = host.to_enc['role::mysql_multiple_rights']['rights']
    enc_rights['mydb']['environment'].should eql('testing')
    enc_rights['mydb']['database_name'].should eql('mydb')

    host.to_enc.should include('server::default_new_mgmt_net_local')
    host.to_enc.should include('mysql_hacks::replication_rights_wrapper')
    host.to_enc.should include('server::default_new_mgmt_net_local')

    host.to_enc['mysql_hacks::replication_rights_wrapper']['rights'].should eql(
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
    enc_server_role['backup'].should eql(true)
    enc_server_role['database_name'].should eql('mydb')
    enc_server_role['datadir'].should eql('/mnt/data/mysql')
    enc_server_role['environment'].should eql('testing')
    enc_server_role['master'].should eql(false)
    enc_server_role['server_id'].should eql(3)

    host.to_enc['mysql_hacks::replication_rights_wrapper']['rights'].should eql(
      'replicant@testing-mydb-001.space.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      },
      'replicant@testing-mydb-002.space.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      }
    )

    host.to_enc.should include('server::default_new_mgmt_net_local')
    host.to_enc.should include('mysql_hacks::replication_rights_wrapper')
    host.to_enc.should_not include('mysql_hacks::application_rights_wrapper')
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
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:type].should eql "data"
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:size].should eql "14G"
    host.to_specs.shift[:storage]['/tmp'.to_sym][:type].should eql "os"
    host.to_specs.shift[:storage]['/tmp'.to_sym][:size].should eql "10G"
  end
  host("testing-mydbbackup-001.mgmt.earth.net.local") do |host|
    host.to_specs.shift[:storage]['/mnt/storage'.to_sym][:size].should eql "29G"
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
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:type].should eql "data"
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:persistent].should eql true
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:size].should eql '10G'
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
    host.to_specs.shift[:ram].should eql '4194304'
    host.to_specs.shift[:vcpus].should eql '2'
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
    host.to_enc['role::mysql_server']['version'].should eql('5.1.49-1ubuntu8')
  end
  host("testing-my55-001.mgmt.space.net.local") do |host|
    host.to_enc['role::mysql_server']['version'].should eql('5.5.43-0ubuntu0.12.04.1')
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
    host.to_enc['role::mysql_server']['dependant_instances'].
      should include('testing-frapp-001.space.net.local', 'testing-frapp-002.space.net.local')
    host.to_enc['role::mysql_server']['dependencies'].should eql({})
  end
  host("testing-hrdb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::mysql_server']['dependant_instances'].
      should_not include('testing-frapp-001.space.net.local', 'testing-frapp-002.space.net.local')
    host.to_enc['role::mysql_server']['dependencies'].should eql({})
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
    enc_server_role['server_id'].should eql(99)
  end
end

describe_stack 'should allow server_id_offset to be specified' do
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
    enc_server_role['server_id'].should eql(1001)
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
    stacks_mysql_config['config']['mysqld']['gtid_mode'].should eql('ON')
    stacks_mysql_config['config']['mysqld']['enforce_gtid_consistency'].should eql('ON')
  end
  host("testing-mydb-002.mgmt.space.net.local") do |host|
    host.to_enc.key?('role::stacks_mysql_config').should eql(false)
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
    stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_size'].should eql('10G')
    stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_instances'].should eql('10')
    stacks_mysql_config['restart_mysql'].should eql(false)
  end
  host("latest-mydb-002.mgmt.space.net.local") do |host|
    stacks_mysql_config = host.to_enc['role::stacks_mysql_config']
    stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_size'].should eql('10G')
    stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_instances'].should eql('10')
    stacks_mysql_config['restart_mysql'].should eql(true)
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
    stacks_mysql_config['config']['mysqld']['innodb_buffer_pool_size'].should eql('10G')
    stacks_mysql_config['config']['mysqld']['gtid_mode'].should eql('ON')
    stacks_mysql_config['config']['mysqld']['enforce_gtid_consistency'].should eql('ON')
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
    stack.should have_hosts(
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
