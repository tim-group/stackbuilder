require 'stacks/environment'
require 'stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack 'loadbalancer' do
      loadbalancer
    end
    stack "example" do
      virtual_proxyserver 'exampleproxy' do
        vhost('exampleapp') do
        end
        enable_nat
      end

      virtual_appserver 'exampleapp' do
        self.groups = ['blue']
        self.application = 'ExAmPLE'
      end

      virtual_appserver 'exampleapp2' do
        self.groups = ['blue']
        self.application = 'example2'
        depend_on "exampleapp"
        depend_on "exampledb"
      end
      virtual_appserver 'exampleapp2' do
        self.groups = ['blue']
        self.application = 'example2'
        depend_on "exampleapp"
        depend_on "exampledb"
      end
    end
    stack "example_db" do
      legacy_mysqldb "exampledb" do
        self.instances = 1
        self.database_name = 'example'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "example"
      instantiate_stack "example_db"
      instantiate_stack "loadbalancer"
    end
  end

  host("e1-lb-001.mgmt.space.net.local") do |host|
    host.to_enc["role::loadbalancer"]["virtual_servers"]["e1-exampleapp-vip.space.net.local"]["realservers"]["blue"].
      should eql([
        "e1-exampleapp-001.space.net.local",
        "e1-exampleapp-002.space.net.local"
      ])
    host.to_enc["role::loadbalancer"]["virtual_servers"]["e1-exampleapp2-vip.space.net.local"]["realservers"]["blue"].
      should eql([
        "e1-exampleapp2-001.space.net.local",
        "e1-exampleapp2-002.space.net.local"
      ])
  end

  host("e1-exampleproxy-001.mgmt.space.net.local") do |host|
    host.to_enc["role::proxyserver"]["vhosts"]["e1-exampleproxy-vip.front.space.net.local"]["proxy_pass_rules"].
      should eql("/" => "http://e1-exampleapp-vip.space.net.local:8000")
  end

  host("e1-exampleapp2-002.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["application_dependant_instances"].should eql([
      'e1-lb-001.space.net.local',
      'e1-lb-002.space.net.local'
    ])
    deps = host.to_enc["role::http_app"]["dependencies"]
    deps["db.example.database"].should eql("example")
    deps["db.example.hostname"].should eql("e1-exampledb-001.space.net.local")
    deps["db.example.password_hiera_key"].should eql("enc/e1/example2/mysql_password")
    deps["db.example.username"].should eql("example2")
    deps['example.url'].should eql('http://e1-exampleapp-vip.space.net.local:8000')
  end
  host("e1-exampleapp-002.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["application_dependant_instances"].should eql([
      "e1-exampleapp2-001.space.net.local",
      "e1-exampleapp2-002.space.net.local",
      "e1-exampleproxy-001.space.net.local",
      "e1-exampleproxy-002.space.net.local",
      'e1-lb-001.space.net.local',
      'e1-lb-002.space.net.local'
    ])
    host.to_enc["role::http_app"]["dependencies"].should eql({})
  end
  host("e1-exampledb-001.mgmt.space.net.local") do |host|
    host.to_enc["role::databaseserver"]["dependant_instances"].should eql([
      "e1-exampleapp2-001.space.net.local",
      "e1-exampleapp2-002.space.net.local"
    ])
    rights = host.to_enc["mysql_hacks::application_rights_wrapper"]['rights']
    rights['example2@e1-exampleapp2-001.space.net.local/example'].should eql(
      'password_hiera_key' => 'enc/e1/example2/mysql_password')
    rights['example2@e1-exampleapp2-002.space.net.local/example'].should eql(
      'password_hiera_key' => 'enc/e1/example2/mysql_password')
  end
end

describe_stack 'stack with dependencies that does not provide config params when specified ' do
  given do
    stack "example" do
      virtual_appserver 'configapp' do
        self.groups = ['blue']
        self.application = 'example'
        depend_on "exampledb"
      end
      virtual_appserver 'noconfigapp' do
        self.groups = ['blue']
        self.application = 'example'
        depend_on "exampledb"
        self.auto_configure_dependencies = false
      end
    end
    stack "example_db" do
      legacy_mysqldb "exampledb" do
        self.instances = 1
        self.database_name = 'example'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "example"
      instantiate_stack "example_db"
    end
  end

  host("e1-configapp-001.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["dependencies"].
      should eql("db.example.database"           => "example",
                 "db.example.hostname"           => "e1-exampledb-001.space.net.local",
                 "db.example.password_hiera_key" => "enc/e1/example/mysql_password",
                 "db.example.username"           => "example")
  end
  host("e1-noconfigapp-001.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["dependencies"].should eql({})
  end
end

describe_stack 'stack with cross environment dependencies' do
  given do
    stack "example" do
      virtual_appserver 'noconfigapp' do
        self.groups = ['blue']
        self.application = 'example'
        case environment.name
        when 'e1'
          depend_on "noconfigapp", "e2"
        when 'e2'
          depend_on "noconfigapp", "e1"
        end
        self.auto_configure_dependencies = false
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "example"
    end

    env "e2", :primary_site => "earth" do
      instantiate_stack "example"
    end
  end

  host("e2-noconfigapp-001.mgmt.earth.net.local") do |host|
    host.to_enc['role::http_app']['application_dependant_instances'].should eql([
      'e1-noconfigapp-001.space.net.local',
      'e1-noconfigapp-002.space.net.local'
    ])
  end
  host("e1-noconfigapp-001.mgmt.space.net.local") do |host|
    host.to_enc['role::http_app']['application_dependant_instances'].should eql([
      'e2-noconfigapp-001.earth.net.local',
      'e2-noconfigapp-002.earth.net.local'
    ])
  end
end

describe_stack 'stack with sub environment dependencies' do
  given do
    stack "blondin" do
      virtual_appserver 'blondinapp' do
        self.groups = ['blue']
        self.application = 'Blondin'
      end
    end

    stack 'funds' do
      virtual_appserver 'fundsuserapp' do
        self.groups = ['blue']
        self.application = 'tfunds'
        self.ports = [8443]
        enable_ajp('8009')
        enable_sso('8443')
        disable_http_lb_hack
      end
    end

    stack 'funds_proxy' do
      virtual_proxyserver 'fundsproxy' do
        @cert = 'wildcard_youdevise_com'
        case environment.name
        when 'shared'
          vhost('fundsuserapp', 'funds-mirror.timgroup.com', 'mirror') do
            @cert = 'wildcard_timgroup_com'
            add_properties 'is_hip' => true
            add_pass_rule "/HIP/resources", :service => "blondinapp", :environment => 'mirror'
          end
        end
        enable_nat
      end
    end

    env 'shared',
        :primary_site => 'oy',
        :secondary_site => 'oy',
        :lb_virtual_router_id => 27 do
      instantiate_stack 'funds_proxy'

      env 'mirror',
          :timcyclic_instances => 1,
          :lb_virtual_router_id => 21 do
        instantiate_stack 'funds'
        instantiate_stack 'blondin'
      end
    end
  end
  host("mirror-blondinapp-001.mgmt.oy.net.local") do |host|
    host.to_enc['role::http_app']['application_dependant_instances'].should include(
      'shared-fundsproxy-001.oy.net.local',
      'shared-fundsproxy-002.oy.net.local')
  end
end
