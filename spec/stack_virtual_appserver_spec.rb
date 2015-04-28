require 'stacks/test_framework'
describe_stack 'stack.virtual_appserver.to_loadbalancer_config' do
  given do
    stack 'fr' do
      virtual_appserver 'frapp' do
        enable_ehcache
        self.application = 'futuresroll'
        self.instances = 2
      end
    end

    env "e1", :primary_site => "space", :lb_virtual_router_id => 66 do
      instantiate_stack "fr"
    end
  end

  host("e1-frapp-001.mgmt.space.net.local") do |host|
    data = host.virtual_service.to_loadbalancer_config(:primary_site)['e1-frapp-vip.space.net.local']
    data['monitor_warn'].should eql(1)
    data['healthcheck_timeout'].should eql(10)
    data['env'].should eql('e1')
    data['app'].should eql('futuresroll')
    data['realservers']['blue'].should eql(["e1-frapp-001.space.net.local", "e1-frapp-002.space.net.local"])
    data['realservers']['green'].should be_nil
  end
end

describe_stack 'enabling tomcat session replication creates the right enc' do
  given do
    stack 'funds' do
      virtual_appserver 'fundsuserapp' do
        @tomcat_session_replication = true
        self.application = 'tfunds'
        self.instances = 3
      end
    end

    env "e1", :primary_site => "space", :lb_virtual_router_id => 66 do
      instantiate_stack "funds"
    end
  end

  host("e1-fundsuserapp-001.mgmt.space.net.local") do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    deps['cluster.enabled'].should eql('true')
    deps['cluster.domain'].should eql('e1-fundsuserapp')
    deps['cluster.members'].should eql('e1-fundsuserapp-002.space.net.local,e1-fundsuserapp-003.space.net.local')
    deps['cluster.receiver.address'].should eql('e1-fundsuserapp-001.space.net.local')
  end
  host("e1-fundsuserapp-002.mgmt.space.net.local") do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    deps['cluster.enabled'].should eql('true')
    deps['cluster.domain'].should eql('e1-fundsuserapp')
    deps['cluster.members'].should eql('e1-fundsuserapp-001.space.net.local,e1-fundsuserapp-003.space.net.local')
    deps['cluster.receiver.address'].should eql('e1-fundsuserapp-002.space.net.local')
  end
  host("e1-fundsuserapp-003.mgmt.space.net.local") do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    deps['cluster.enabled'].should eql('true')
    deps['cluster.domain'].should eql('e1-fundsuserapp')
    deps['cluster.members'].should eql('e1-fundsuserapp-001.space.net.local,e1-fundsuserapp-002.space.net.local')
    deps['cluster.receiver.address'].should eql('e1-fundsuserapp-003.space.net.local')
  end
end
