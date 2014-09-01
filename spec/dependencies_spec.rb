require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack 'loadbalancer' do
      loadbalancer
    end
    stack "example" do
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
      mysqldb "exampledb"
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

  host("e1-exampleapp2-002.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["dependant_instances"].should eql([
        'e1-lb-001.space.net.local',
        'e1-lb-002.space.net.local'
    ])
    host.to_enc["role::http_app"]["dependencies"].should eql([
       ['example.url', 'http://e1-exampleapp-vip.space.net.local:8000']
    ])
  end
  host("e1-exampleapp-002.mgmt.space.net.local") do |host|
    host.to_enc["role::http_app"]["dependant_instances"].should eql([
      "e1-exampleapp2-001.space.net.local",
      "e1-exampleapp2-002.space.net.local",
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
    host.to_enc["role::databaseserver"]["dependencies"].should eql([])
  end

end
