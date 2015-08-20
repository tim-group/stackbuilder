require 'matchers/server_matcher'
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
        if %w(e1) == environment.name
          depend_on("exampledb", "e1", :primary_site)
        else
          depend_on("exampledb", "e1", :secondary_site)
        end
      end
    end

    stack "example_db" do
      mysql_cluster 'exampledb' do
        self.database_name = "example"
        self.backup_instances = 1
        self.slave_instances = 2
        self.secondary_site_slave_instances = 1
        self.include_master_in_read_only_cluster = false
      end
    end

    env "e1", :primary_site => "space", :secondary_site => "earth" do
      instantiate_stack "example_db"
      instantiate_stack "example"
    end

    env "e2", :primary_site => "earth", :secondary_site => "space" do
      instantiate_stack "loadbalancer"
      instantiate_stack "example"
    end
  end

  host("e2-exampleapp2-002.mgmt.earth.net.local") do |host|
    deps = host.to_enc["role::http_app"]["dependencies"]

    deps["db.example.database"].should eql("example")
    deps["db.example.hostname"].should eql("e1-exampledb-001.space.net.local")
    deps["db.example.port"].should eql("3306")
    deps["db.example.password_hiera_key"].should eql("enc/e2/example2/mysql_password")
    deps["db.example.username"].should eql("example2")
    deps["db.example.read_only_cluster"].should eql(
      "e1-exampledb-001.earth.net.local" \
    )
  end

  host("e1-exampleapp2-002.mgmt.space.net.local") do |host|
    deps = host.to_enc["role::http_app"]["dependencies"]

    deps["db.example.database"].should eql("example")
    deps["db.example.hostname"].should eql("e1-exampledb-001.space.net.local")
    deps["db.example.port"].should eql("3306")
    deps["db.example.password_hiera_key"].should eql("enc/e1/example2/mysql_password")
    deps["db.example.username"].should eql("example2")
    deps["db.example.read_only_cluster"].should eql(
      "e1-exampledb-002.space.net.local,e1-exampledb-003.space.net.local" \
    )
  end
end
