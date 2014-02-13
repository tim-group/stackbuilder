require 'stacks/test_framework'

describe_stack 'stack-with-dependencies' do
  given do
    stack "example" do
      virtual_appserver 'exampleapp' do
        self.groups = ['blue']
        self.application = 'example'
      end

      virtual_appserver 'exampleapp2' do
        self.groups = ['blue']
        self.application = 'example2'
        self.depends_on = ["exampleapp"]
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "example"
    end
  end

  host("e1-exampleapp2-002.mgmt.space.net.local") do |host|
    host.to_enc.should eql(
       {"role::http_app"=>
         {"group"=>"blue",
          "vip_fqdn"=>"e1-exampleapp2-vip.space.net.local",
          "application"=>"example2",
          "environment" => "e1",
          "dependencies" => {
              'example.url' => 'http://e1-exampleapp-vip.space.net.local:8000'
           },
          "dependant_instances" => []
         }
    })
  end

  host("e1-exampleapp-002.mgmt.space.net.local") do |host|
    host.to_enc.should eql(
                           {"role::http_app"=>
                                {"group"=>"blue",
                                 "vip_fqdn"=>"e1-exampleapp-vip.space.net.local",
                                 "application"=>"example",
                                 "environment" => "e1",
                                 "dependencies" => {},
                                 "dependant_instances" => ["e1-exampleapp2-001.space.net.local","e1-exampleapp2-002.space.net.local"]
                                }
                           })
  end
end
