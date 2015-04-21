require 'stacks/test_framework'
describe_stack 'load balancers in multiple sites create the correct load balancing config in each site' do
  given do
    stack "lb" do
      loadbalancer  do
        @enable_secondary_site = true
      end
    end

    stack "funds" do
      virtual_appserver 'fundsapp' do
        @enable_secondary_site = true
      end
    end

    env 'e1', :primary_site => 'mars', :secondary_site => 'jupiter' do
      instantiate_stack 'lb'
      instantiate_stack 'funds'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    stack.should have_hosts([
                            'e1-lb-001.mgmt.mars.net.local',
                            'e1-lb-002.mgmt.mars.net.local',
                            'e1-lb-001.mgmt.jupiter.net.local',
                            'e1-lb-002.mgmt.jupiter.net.local',
                            'e1-fundsapp-001.mgmt.mars.net.local',
                            'e1-fundsapp-002.mgmt.mars.net.local',
                            'e1-fundsapp-001.mgmt.jupiter.net.local',
                            'e1-fundsapp-002.mgmt.jupiter.net.local',
    ])
  end
  it_stack 'should create load balancers in both sites with the correct lb config' do |stack|

    host("e1-lb-001.mgmt.mars.net.local") do |host|
      enc = host.to_enc['role::loadbalancer']['virtual_servers']
      enc['e1-fundsapp-vip.mars.net.local']['realservers']['blue'].should eql(['e1-fundsapp-001.mars.net.local', 'e1-fundsapp-002.mars.net.local'])
    end

    host("e1-lb-001.mgmt.jupiter.net.local") do |host|
      enc = host.to_enc['role::loadbalancer']['virtual_servers']
      enc['e1-fundsapp-vip.jupiter.net.local']['realservers']['blue'].should eql(['e1-fundsapp-001.jupiter.net.local', 'e1-fundsapp-002.jupiter.net.local'])
    end
  end
end

describe_stack 'load balancer stack create a secondary server with the correct enc and spec information' do
   given do
     stack "lb" do
       loadbalancer  do
         each_machine do |machine|
           machine.add_route('mgmt_pg_from_mgmt_oy')
         end
       end
     end

     stack 'fr' do
       virtual_appserver 'frapp' do
         enable_ehcache
         self.application = 'futuresroll'
         self.instances = 2
       end
     end

     env "e1", :primary_site => "space", :lb_virtual_router_id => 66 do
       instantiate_stack "lb"
       instantiate_stack "fr"
     end
   end

   host("e1-lb-002.mgmt.space.net.local") do |host|
     host.to_enc['role::loadbalancer']['virtual_router_id'].should eql(66)
     host.to_enc['role::loadbalancer']['virtual_servers']['e1-frapp-vip.space.net.local'].should eql(
       "env" => "e1",
       "monitor_warn" => 1,
       "app" => "futuresroll",
       "realservers" => {
         "blue" => ["e1-frapp-001.space.net.local", "e1-frapp-002.space.net.local"]
       },
       "healthcheck_timeout" => 10
     )
     host.to_enc['routes'].should eql("to" => ["mgmt_pg_from_mgmt_oy"])
     host.to_specs.shift[:qualified_hostnames].should eql(:mgmt => "e1-lb-002.mgmt.space.net.local",
                                                         :prod => "e1-lb-002.space.net.local")
     host.to_specs.shift[:availability_group].should eql('e1-lb')
     host.to_specs.shift[:networks].should eql([:mgmt, :prod])
     host.to_specs.shift[:hostname].should eql('e1-lb-002')
     host.to_specs.shift[:domain].should eql('space.net.local')
   end
end

