require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack.app_service.to_loadbalancer_config' do
  given do
    stack 'fr' do
      app_service 'frapp' do
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
    data = host.virtual_service.to_loadbalancer_config(:primary_site, 'space')['e1-frapp-vip.space.net.local']
    expect(data['monitor_warn']).to eql(1)
    expect(data['healthcheck_timeout']).to eql(10)
    expect(data['env']).to eql('e1')
    expect(data['app']).to eql('futuresroll')
    expect(data['realservers']['blue']).to eql(["e1-frapp-001.space.net.local", "e1-frapp-002.space.net.local"])
    expect(data['realservers']['green']).to be_nil
  end
end

describe_stack 'enabling tomcat session replication creates the right enc' do
  given do
    stack 'funds' do
      app_service 'fundsuserapp' do
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
    expect(deps['cluster.enabled']).to eql('true')
    expect(deps['cluster.domain']).to eql('e1-fundsuserapp')
    expect(deps['cluster.members']).to eql('e1-fundsuserapp-002.space.net.local,e1-fundsuserapp-003.space.net.local')
    expect(deps['cluster.receiver.address']).to eql('e1-fundsuserapp-001.space.net.local')
  end
  host("e1-fundsuserapp-002.mgmt.space.net.local") do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['cluster.enabled']).to eql('true')
    expect(deps['cluster.domain']).to eql('e1-fundsuserapp')
    expect(deps['cluster.members']).to eql('e1-fundsuserapp-001.space.net.local,e1-fundsuserapp-003.space.net.local')
    expect(deps['cluster.receiver.address']).to eql('e1-fundsuserapp-002.space.net.local')
  end
  host("e1-fundsuserapp-003.mgmt.space.net.local") do |host|
    deps = host.to_enc['role::http_app']['dependencies']
    expect(deps['cluster.enabled']).to eql('true')
    expect(deps['cluster.domain']).to eql('e1-fundsuserapp')
    expect(deps['cluster.members']).to eql('e1-fundsuserapp-001.space.net.local,e1-fundsuserapp-002.space.net.local')
    expect(deps['cluster.receiver.address']).to eql('e1-fundsuserapp-003.space.net.local')
  end
end
