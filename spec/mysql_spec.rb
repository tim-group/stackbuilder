require 'stacks/test_framework'

describe_stack 'should provide a legacy mode to be backwards compatible with old mysqldb code' do

  given do
    stack "mysql" do
      mysql_cluster "frdb" do
        self.legacy_mode
      end
    end

    env "testing", :primary_site=>"space" do
      instantiate_stack "mysql"
    end
  end

  host("testing-frdb-001.mgmt.space.net.local") do |host|
    host.master?.should eql true
    host.to_enc['role::databaseserver']['dependant_instances'].should eql nil
  end
end
describe_stack 'should provide 3 mysql servers by default, one is a master' do

  given do
    stack "mysql" do
      mysql_cluster "frdb"
    end

    env "testing", :primary_site=>"space" do
      instantiate_stack "mysql"
    end
  end

  host("testing-frdb-001.mgmt.space.net.local") do |host|
    host.master?.should eql true
    host.backup?.should eql false
    host.to_enc['role::databaseserver']['dependant_instances'].should eql([
      'testing-frdb-002.space.net.local',
      'testing-frdbbackup-001.space.net.local',
    ])
  end
  host("testing-frdb-002.mgmt.space.net.local") do |host|
    host.master?.should eql false
    host.backup?.should eql false
  end
  host("testing-frdbbackup-001.mgmt.space.net.local") do |host|
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

    env "testing", :primary_site=>"space" do
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
    env "testing", :primary_site=>"space" do
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
    env "testing", :primary_site=>"space" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::databaseserver']['database_name'].should eql 'mydb'
    host.to_enc['role::databaseserver']['application'].should eql false
    host.to_enc['role::databaseserver']['environment'].should eql 'testing'
    host.to_enc['role::databaseserver']['restart_on_config_change'].should eql false
    host.to_enc['role::databaseserver']['restart_on_install'].should eql true
    host.to_enc['role::databaseserver']['datadir'].should eql '/mnt/data/mysql'
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
    env "testing", :primary_site=>"space" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:type].should eql "data"
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:size].should eql "14G"
  end
  host("testing-mydbbackup-001.mgmt.space.net.local") do |host|
    host.to_specs.shift[:storage]['/mnt/storage'.to_sym][:size].should eql "29G"
  end
end

describe_stack 'should always provide a default data mount of /mnt/data with sensible defaults' do
  given do
    stack "mysql" do
      mysql_cluster "mydb" do
      end
    end
    env "testing", :primary_site=>"space" do
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
    env "testing", :primary_site=>"space" do
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
        self.depends_on = 'frdb'
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

    env "testing", :primary_site=>"space" do
      instantiate_stack "fr"
      instantiate_stack "fr_db"
      instantiate_stack "hr"
      instantiate_stack "hr_db"
    end
  end
  host("testing-frdb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::databaseserver']['dependant_instances'].should include('testing-frapp-001.space.net.local', 'testing-frapp-002.space.net.local')
    host.to_enc['role::databaseserver']['dependencies'].should eql({})
  end
  host("testing-hrdb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::databaseserver']['dependant_instances'].should_not include('testing-frapp-001.space.net.local','testing-frapp-002.space.net.local')
    host.to_enc['role::databaseserver']['dependencies'].should eql({})
  end
end