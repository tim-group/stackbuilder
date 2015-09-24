require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'should default to disallow destory' do
  given do
    stack "mysql" do
      legacy_mysqldb "mydb"
    end

    env "testing", :primary_site => "space" do
      instantiate_stack "mysql"
    end
  end

  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.destroyable?).to eql false
    expect(host.to_specs.shift[:disallow_destroy]).to eql true
  end
end

describe_stack 'should allow destroy to be overwritten' do
  given do
    stack "mysql" do
      legacy_mysqldb "mydb" do
        each_machine(&:allow_destroy)
      end
    end
    env "testing", :primary_site => "space" do
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
      legacy_mysqldb "mydb" do
        self.database_name = "mydb"
        each_machine(&:allow_destroy)
      end
    end
    env "testing", :primary_site => "space" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::databaseserver']['database_name']).to eql 'mydb'
    expect(host.to_enc['role::databaseserver']['application']).to eql false
    expect(host.to_enc['role::databaseserver']['environment']).to eql 'testing'
    expect(host.to_enc['role::databaseserver']['restart_on_config_change']).to eql false
    expect(host.to_enc['role::databaseserver']['restart_on_install']).to eql true
    expect(host.to_enc['role::databaseserver']['datadir']).to eql '/mnt/data/mysql'
  end
end

describe_stack 'should allow storage options to be overwritten' do
  given do
    stack "mysql" do
      legacy_mysqldb "mydb" do
        self.database_name = "mydb"
        each_machine do |machine|
          machine.modify_storage('/'              => { :size => '5G' },
                                 '/var/lib/mysql' => { :type => 'data', :size => '10G' })
        end
      end
    end
    env "testing", :primary_site => "space" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.shift[:storage]['/var/lib/mysql'.to_sym]).to include(:type => "data")
    expect(host.to_specs.shift[:storage]['/var/lib/mysql'.to_sym]).to include(:size => "10G")
    expect(host.to_specs.shift[:storage]['/'.to_sym]).to include(:type => "os")
    expect(host.to_specs.shift[:storage]['/'.to_sym]).to include(:size => "5G")
  end
end

describe_stack 'should always provide a default data mount of /mnt/data with sensible defaults' do
  given do
    stack "mysql" do
      legacy_mysqldb "mydb" do
      end
    end
    env "testing", :primary_site => "space" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:type]).to eql "data"
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:persistent]).to eql true
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:size]).to eql '10G'
    expect(host.to_specs.shift[:storage]['/mnt/data'.to_sym][:persistence_options][:on_storage_not_found]).
      to eql 'raise_error'
  end
end

describe_stack 'should provide a default of 4GB of ram and 2 cpu cores' do
  given do
    stack "mysql" do
      legacy_mysqldb "mydb" do
      end
    end
    env "testing", :primary_site => "space" do
      instantiate_stack "mysql"
    end
  end
  host("testing-mydb-001.mgmt.space.net.local") do |host|
    expect(host.to_specs.shift[:ram]).to eql '4194304'
    expect(host.to_specs.shift[:vcpus]).to eql '2'
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
      legacy_mysqldb 'frdb' do
        self.database_name = "futuresroll"
      end
    end
    stack 'hr' do
      virtual_appserver 'hrapp' do
        self.application = 'huturesroll'
      end
    end
    stack 'hr_db' do
      legacy_mysqldb 'hrdb' do
        self.database_name = "huturesroll"
      end
    end

    env "testing", :primary_site => "space" do
      instantiate_stack "fr"
      instantiate_stack "fr_db"
      instantiate_stack "hr"
      instantiate_stack "hr_db"
    end
  end
  host("testing-frdb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::databaseserver']['dependant_instances']).to \
      eql(['testing-frapp-001.space.net.local', 'testing-frapp-002.space.net.local'])
    expect(host.to_enc['role::databaseserver']['dependencies']).to eql({})
  end
  host("testing-hrdb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::databaseserver']['dependant_instances']).to be_nil
    expect(host.to_enc['role::databaseserver']['dependencies']).to be_nil
  end
end

describe_stack 'should have mysql 5.1.49-1ubuntu8 as the default version of mysql' do
  given do
    stack 'fr_db' do
      legacy_mysqldb 'frdb' do
        self.database_name = "futuresroll"
      end
    end
    stack 'hr_db' do
      legacy_mysqldb 'hrdb' do
        self.database_name = "huturesroll"
        each_machine { |machine| machine.version = '5.5.43-0ubuntu0.12.04.1' }
      end
    end

    env "testing", :primary_site => "space" do
      instantiate_stack "fr_db"
      instantiate_stack "hr_db"
    end
  end
  host("testing-frdb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::databaseserver']['version']).to eql('5.1.49-1ubuntu8')
  end
  host("testing-hrdb-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::databaseserver']['version']).to eql('5.5.43-0ubuntu0.12.04.1')
  end
end
