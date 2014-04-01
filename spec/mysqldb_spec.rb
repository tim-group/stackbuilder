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

    stack "nodestroy" do
      mysqldb "nodestroydb" do
        self.instances = 1
       each_machine do |machine|
          machine.database_name = "mydb"
          machine.application = "myapp"
          machine.image_size = '5G'
          machine.ram = '4194304'
        end
      end
    end

    stack "allowdestroy" do
      mysqldb "allowdestroydb" do
        self.instances = 1
       each_machine do |machine|
          machine.allow_destroy()
          machine.database_name = "mydb"
          machine.application = "myapp"
          machine.image_size = '5G'
          machine.ram = '4194304'
        end
      end
    end
    env "testing", :primary_site=>"space" do
      instantiate_stack "myapp"
      instantiate_stack "nodestroy"
      instantiate_stack "allowdestroy"
    end
  end

  host("testing-nodestroydb-001.mgmt.space.net.local") do |host|
    host.to_specs.should eql([
      {:fabric=>"space",
       :disallow_destroy => true,
       :qualified_hostnames=>{
          :mgmt=>"testing-nodestroydb-001.mgmt.space.net.local",
          :prod=>"testing-nodestroydb-001.space.net.local"},
        :availability_group=>"testing-nodestroydb",
        :networks=>[:mgmt, :prod],
        :hostname=>"testing-nodestroydb-001",
        :ram=>"4194304",
        :image_size=>"5G",
        :domain=>"space.net.local"}])

  end

  host("testing-allowdestroydb-001.mgmt.space.net.local") do |host|
    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"testing-allowdestroydb-001.mgmt.space.net.local",
          :prod=>"testing-allowdestroydb-001.space.net.local"},
        :availability_group=>"testing-allowdestroydb",
        :networks=>[:mgmt, :prod],
        :hostname=>"testing-allowdestroydb-001",
        :ram=>"4194304",
        :image_size=>"5G",
        :domain=>"space.net.local"}])

  end

  host("testing-mydb-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::databaseserver' => {
        'application' => 'myapp',
        'database_name' => 'mydb',
        'environment' => 'testing',
        'restart_on_config_change' => true
      }})
  end
end
