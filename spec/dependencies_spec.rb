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
        self.depends_on = ["exampleapp", "exampledb"]
      end
    end
    stack "example_db" do
      mysqldb "exampledb" do
        self.instances = 1
        self.database_name = 'example'
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "example"
      instantiate_stack "example_db"
      instantiate_stack "loadbalancer"
    end
  end

  host("e1-lb-001.mgmt.space.net.local") do |host|
     host.to_enc["role::loadbalancer"]["virtual_servers"]["e1-exampleapp-vip.space.net.local"]["realservers"]["blue"].should eql([
      "e1-exampleapp-001.space.net.local",
      "e1-exampleapp-002.space.net.local"
     ])
     host.to_enc["role::loadbalancer"]["virtual_servers"]["e1-exampleapp2-vip.space.net.local"]["realservers"]["blue"].should eql([
      "e1-exampleapp2-001.space.net.local",
      "e1-exampleapp2-002.space.net.local"
     ])
  end

  host("e1-exampleproxy-001.mgmt.space.net.local") do |host|
    host.to_enc["role::proxyserver"]["vhosts"]["e1-exampleproxy-vip.front.space.net.local"]["proxy_pass_rules"].should eql({"/"=>"http://e1-exampleapp-vip.space.net.local:8000"})
  end

  host("e1-exampleapp2-002.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["dependant_instances"].should eql([
        'e1-lb-001.space.net.local',
        'e1-lb-002.space.net.local'
    ])
    host.to_enc["role::http_app"]["dependencies"].should eql([
       ["db.example.database", "example"],
       ["db.example.hostname", "e1-exampledb-001.space.net.local"],
       ["db.example.password_hiera_key", "enc/e1/example2/mysql_password"],
       ["db.example.username", "example2"],
       ['example.url', 'http://e1-exampleapp-vip.space.net.local:8000'],
    ])
  end
  host("e1-exampleapp-002.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["dependant_instances"].should eql([
      "e1-exampleapp2-001.space.net.local",
      "e1-exampleapp2-002.space.net.local",
      "e1-exampleproxy-001.space.net.local",
      "e1-exampleproxy-002.space.net.local",
      'e1-lb-001.space.net.local',
      'e1-lb-002.space.net.local'
    ])
    host.to_enc["role::http_app"]["dependencies"].should eql([])
  end
  host("e1-exampledb-001.mgmt.space.net.local") do |host|
    host.to_enc["role::databaseserver"]["dependant_instances"].should eql([
      "e1-exampleapp2-001.space.net.local",
      "e1-exampleapp2-002.space.net.local"
    ])
    host.to_enc["mysql_hacks::application_rights_wrapper"]['rights']['example2@e1-exampleapp2-001.space.net.local/example'].should eql({
      'password_hiera_key' => 'enc/e1/example2/mysql_password',
    })
    host.to_enc["mysql_hacks::application_rights_wrapper"]['rights']['example2@e1-exampleapp2-002.space.net.local/example'].should eql({
      'password_hiera_key' => 'enc/e1/example2/mysql_password',
    })
  end

end
