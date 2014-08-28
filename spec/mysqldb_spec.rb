require 'stacks/test_framework'


describe_stack 'should default to disallow destory' do

  given do
    stack "mysql" do
      mysqldb "mydb"
    end

    env "testing", :primary_site=>"space" do
      instantiate_stack "mysql"
    end
  end

  host("testing-mydb-001.mgmt.space.net.local") do |host|
    host.destroyable?.should eql false
    host.to_specs.shift[:disallow_destroy].should eql true
  end
end

describe_stack 'should allow destroy to be overwritten' do
  given do
    stack "mysql" do
      mysqldb "mydb" do
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
      mysqldb "mydb" do
       self.database_name = "mydb"
       self.application = "myapp"
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
    host.to_enc['role::databaseserver']['application'].should eql 'myapp'
    host.to_enc['role::databaseserver']['database_name'].should eql 'mydb'
    host.to_enc['role::databaseserver']['environment'].should eql 'testing'
    host.to_enc['role::databaseserver']['restart_on_config_change'].should eql false
    host.to_enc['role::databaseserver']['restart_on_install'].should eql true
  end
end

describe_stack 'should allow storage options to be overwritten' do
  given do
    stack "mysql" do
      mysqldb "mydb" do
       self.database_name = "mydb"
       self.application = "myapp"
       each_machine do |machine|
          machine.modify_storage({
            '/'              => { :size => '5G' },
            '/var/lib/mysql' => { :type => 'data', :size => '10G' },
          })
        end
      end
    end
    env "testing", :primary_site=>"space" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    host.to_specs.shift[:storage]['/var/lib/mysql'.to_sym].should include(:type=>"data")
    host.to_specs.shift[:storage]['/var/lib/mysql'.to_sym].should include(:size=>"10G")
    host.to_specs.shift[:storage]['/'.to_sym].should include(:type=>"os")
    host.to_specs.shift[:storage]['/'.to_sym].should include(:size =>"5G")
  end
end

describe_stack 'should always provide a default data mount of /mnt/data with sensible defaults' do
  given do
    stack "mysql" do
      mysqldb "mydb" do
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
    host.to_specs.shift[:storage]['/mnt/data'.to_sym][:persistence_options][:on_storage_not_found].should eql :raise_error
  end

end

describe_stack 'should provide a default of 4GB of ram and 2 cpu cores' do
  given do
    stack "mysql" do
      mysqldb "mydb" do
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
        self.depends_on = ["frdb"]
      end
    end
    stack 'fr_db' do
      mysqldb 'frdb' do
        self.database_name = "futuresroll"
        self.application = "futuresroll"
      end
    end
    stack 'hr' do
      virtual_appserver 'hrapp' do
        self.application = 'huturesroll'
      end
    end
    stack 'hr_db' do
      mysqldb 'hrdb' do
        self.database_name = "huturesroll"
        self.application = "huturesroll"
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
    host.to_enc['role::databaseserver']['allowed_hosts'].should eql(['testing-frapp-001.space.net.local', 'testing-frapp-002.space.net.local'])
  end
  host("testing-hrdb-001.mgmt.space.net.local") do |host|
    host.to_enc['role::databaseserver']['allowed_hosts'].should be_nil
  end
end
