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
        if "e1" == environment.name
          depend_on("exampledb", "e1")
        elsif "pg" == environment.name
          depend_on("exampledb", "pg")
        else
          depend_on("exampledb", "e1")
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
      env 'pg', :production => true do
        instantiate_stack "example_db"
        instantiate_stack "example"
      end

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
    expect(deps["db.example.database"]).to eql("example")
    expect(deps["db.example.hostname"]).to eql("e1-exampledb-001.space.net.local")
    expect(deps["db.example.port"]).to eql("3306")
    expect(deps["db.example.password_hiera_key"]).to eql("enc/e2/example2/mysql_password")
    expect(deps["db.example.username"]).to eql("example2")
    expect(deps["db.example.read_only_cluster"]).to eql(
      "e1-exampledb-001.earth.net.local" \
    )
  end

  host("e1-exampleapp2-002.mgmt.space.net.local") do |host|
    deps = host.to_enc["role::http_app"]["dependencies"]

    expect(deps["db.example.database"]).to eql("example")
    expect(deps["db.example.hostname"]).to eql("e1-exampledb-001.space.net.local")
    expect(deps["db.example.port"]).to eql("3306")
    expect(deps["db.example.password_hiera_key"]).to eql("enc/e1/example2/mysql_password")
    expect(deps["db.example.username"]).to eql("example2")
    expect(deps["db.example.read_only_cluster"]).to eql(
      "e1-exampledb-002.space.net.local,e1-exampledb-003.space.net.local" \
    )
  end

  host("pg-exampleapp2-002.mgmt.space.net.local") do |host|
    deps = host.to_enc["role::http_app"]["dependencies"]

    expect(deps["db.example.database"]).to eql("example")
    expect(deps["db.example.hostname"]).to eql("pg-exampledb-001.space.net.local")
    expect(deps["db.example.port"]).to eql("3306")
    expect(deps["db.example.password_hiera_key"]).to eql("enc/pg/example2/mysql_password")
    expect(deps["db.example.username"]).to eql("example2")
    expect(deps["db.example.read_only_cluster"]).to eql(
      "pg-exampledb-002.space.net.local,pg-exampledb-003.space.net.local" \
    )
  end
end
