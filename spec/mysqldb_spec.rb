require 'stacks/test_framework'

describe_stack 'myapp' do
  given do
    stack "myapp" do
      mysqldb "mydb" do
        self.instances = 1
        each_machine do |machine|                                                   
          machine.database_name = "mydb"                                             
          machine.application = "myapp"
          machine.image_size = '5G' 
          machine.ram = '4194304'
        end
      end
    end

    env "testing", :primary_site=>"space" do
      instantiate_stack "myapp"
    end
  end

  host("testing-mydb-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::databaseserver' => {
        'application' => 'myapp', 
        'database_name' => 'mydb',
        'environment' => 'testing',
        'restart_on_config_change' => true
      }})

    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"testing-mydb-001.mgmt.space.net.local",
          :prod=>"testing-mydb-001.space.net.local"},
        :availability_group=>"testing-mydb",
        :networks=>[:mgmt, :prod],
        :hostname=>"testing-mydb-001",
        :ram=>"4194304",
        :image_size=>"5G",
        :domain=>"space.net.local"}])

  end
end
