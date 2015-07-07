require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack 'loadbalancer' do
      loadbalancer
    end
    stack "example" do
      virtual_appserver 'exampleapp2' do
        self.groups = ['blue']
        self.application = 'example2'
        depend_on "exampledb"
      end
    end
    stack "example_db" do
      mysql_cluster 'exampledb' do
        self.database_name = "example"
        self.backup_instances = 1
        self.slave_instances = 2
      end
    end

    env "e1", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "example"
      instantiate_stack "example_db"
      instantiate_stack "loadbalancer"
    end
  end

  host("e1-exampleapp2-002.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["application_dependant_instances"].should eql([
      'e1-lb-001.space.net.local',
      'e1-lb-002.space.net.local',
    ])
    deps = host.to_enc["role::http_app"]["dependencies"]
    deps["db.example.database"].should eql("example")
    deps["db.example.hostname"].should eql("e1-exampledb-001.space.net.local")
    deps["db.example.password_hiera_key"].should eql("enc/e1/example2/mysql_password")
    deps["db.example.username"].should eql("example2")
    deps["db.example.secondary_hostnames"].should eql(
      "e1-exampledb-002.space.net.local,e1-exampledb-003.space.net.local",
    )
    deps["db.example.read_only_cluster"].should eql(
      "\"e1-exampledb-001.space.net.local,e1-exampledb-002.space.net.local,e1-exampledb-003.space.net.local\"",
    )
  end
end
