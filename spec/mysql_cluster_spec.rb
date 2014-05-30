require 'stacks/test_framework'

describe_stack 'can define a mysql cluster with fields at the machine level' do
  given do
    stack "example" do
      mysqldb 'ideasfxdb' do
        self.instances = 1
        each_machine do |machine|
          machine.database_name = "ideasfx"
          machine.application = "ideasfx"
          machine.image_size = '50G'
          machine.ram = '1048576'
          machine.vcpus = '4'
          machine.allow_destroy
         end
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "example"
    end
  end

  host("e1-ideasfxdb-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql(
      {"role::databaseserver"=>
       {"application"=>"ideasfx",
        "restart_on_config_change"=>true,
        "database_name"=>"ideasfx",
        "environment"=>"e1"}}
    )
  end
end

describe_stack 'can define a mysql cluster with fields at the cluster level' do
  given do
    stack "example" do
      mysqldb 'ideasfxdb' do
        self.instances = 1
        self.database_name = 'ideasfx'
        self.application = 'ideasfx'

        each_machine do |machine|
          machine.image_size = '50G'
          machine.ram = '1048576'
          machine.vcpus = '4'
          machine.allow_destroy
        end
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "example"
    end
  end

  host("e1-ideasfxdb-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql(
      {"role::databaseserver"=>
       {"application"=>"ideasfx",
        "restart_on_config_change"=>true,
        "database_name"=>"ideasfx",
        "environment"=>"e1"}}
    )
  end
end
