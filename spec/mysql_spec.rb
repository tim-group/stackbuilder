require 'stacks/test_framework'

describe_stack 'should provide a single instance mode to be backwards compatible with old mysqldb code' do

  given do
    stack "mysql" do
      mysql_cluster "frdb" do
        self.single_instance
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
    host.to_enc['networking::routing::to_site'].should eql({
      'network' => 'prod',
      'site'    => 'oy'
    })
  end
  host("testing-frdb-002.mgmt.pg.net.local") do |host|
    host.to_enc['networking::routing::to_site'].should eql({
      'network' => 'prod',
      'site'    => 'oy'
    })
  end
  host("testing-frdbbackup-001.mgmt.oy.net.local") do |host|
    host.to_enc['networking::routing::to_site'].should eql({
      'network' => 'prod',
      'site'    => 'pg'
    })
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
      'testing-frdbbackup-001.earth.net.local',
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
        each_machine do |machine|
           machine.allow_destroy()
         end
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
        each_machine do |machine|
           machine.allow_destroy()
         end
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    enc_server_role['backup'].should eql(false)
    enc_server_role['config'].should eql({})
    enc_server_role['database_name'].should eql('mydb')
    enc_server_role['datadir'].should eql('/mnt/data/mysql')
    enc_server_role['environment'].should eql('testing')
    enc_server_role['master'].should eql(true)
    enc_server_role['server_id'].should eql(1)

    enc_rights = host.to_enc['role::mysql_multiple_rights']['rights']
    enc_rights['mydb']['environment'].should eql('testing')
    enc_rights['mydb']['database_name'].should eql('mydb')

    host.to_enc.should include('server::default_new_mgmt_net_local')
    host.to_enc['mysql_hacks::replication_rights_wrapper']['rights'].should eql({
      'replicant@testing-mydb-002.space.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      },
      'replicant@testing-mydbbackup-001.earth.net.local' => {
        'password_hiera_key' => 'enc/testing/mydb/replication/mysql_password'
      }
    })
  end
  host("testing-mydb-002.mgmt.space.net.local") do |host|
    enc_server_role = host.to_enc['role::mysql_server']
    enc_server_role['backup'].should eql(false)
    enc_server_role['config'].should eql({})
    enc_server_role['database_name'].should eql('mydb')
    enc_server_role['datadir'].should eql('/mnt/data/mysql')
    enc_server_role['environment'].should eql('testing')
    enc_server_role['master'].should eql(false)
    enc_server_role['server_id'].should eql(2)

    enc_rights = host.to_enc['role::mysql_multiple_rights']['rights']
    enc_rights['mydb']['environment'].should eql('testing')
    enc_rights['mydb']['database_name'].should eql('mydb')

    host.to_enc.should include('server::default_new_mgmt_net_local')
    host.to_enc.should_not include('mysql_hacks::replication_rights_wrapper')
  end
  host("testing-mydbbackup-001.mgmt.earth.net.local") do |host|
     enc_server_role = host.to_enc['role::mysql_server']
     enc_server_role['backup'].should eql(true)
     enc_server_role['config'].should eql({})
     enc_server_role['database_name'].should eql('mydb')
     enc_server_role['datadir'].should eql('/mnt/data/mysql')
     enc_server_role['environment'].should eql('testing')
     enc_server_role['master'].should eql(false)
     enc_server_role['server_id'].should eql(3)

     host.to_enc.should include('server::default_new_mgmt_net_local')
     host.to_enc.should_not include('mysql_hacks::replication_rights_wrapper')
     host.to_enc.should_not include('mysql_hacks::application_rights_wrapper')
   end
end

describe_stack 'should allow storage options to be overwritten' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
        self.database_name = "mydb"
        self.data_size('14G')
        self.backup_size('29G')
      end
    end
    env "testing", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:type].should eql "data"
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:size].should eql "14G"
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
    host.to_enc['role::mysql_server']['dependant_instances'].should include('testing-frapp-001.space.net.local', 'testing-frapp-002.space.net.local')
    host.to_enc['role::mysql_server']['dependencies'].should eql({})
  end
  host("testing-hrdb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::mysql_server']['dependant_instances'].should_not include('testing-frapp-001.space.net.local', 'testing-frapp-002.space.net.local')
    host.to_enc['role::mysql_server']['dependencies'].should eql({})
  end
end
