require 'stacks/test_framework'
describe_stack 'stack.virtual_appserver.to_loadbalancer_config for sso' do
  given do
    stack 'test' do
      virtual_appserver 'testapp' do
        enable_ehcache
        enable_sso('8443')
        enable_ajp('8009')
        disable_http_lb_hack
        self.application = 'test_application'
        self.instances = 2
      end
    end

    stack 'test_stack_2' do
      virtual_appserver 'testapp2' do
        enable_ehcache
        enable_sso('8443')
        self.application = 'test_application'
        self.instances = 2
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "test"
      instantiate_stack "test_stack_2"
    end
  end

  host("e1-testapp-001.mgmt.space.net.local") do |host|
    data = host.virtual_service.to_loadbalancer_config['e1-testapp-vip.space.net.local']
    data['monitor_warn'].should eql(1)
    data['healthcheck_timeout'].should eql(10)
    data['env'].should eql('e1')
    data['app'].should eql('test_application')
    data['type'].should eql('sso_app')
    data['realservers']['blue'].should eql(["e1-testapp-001.space.net.local", "e1-testapp-002.space.net.local"])
    data['realservers']['green'].should be_nil

    host.to_enc['role::http_app']['port'].should eql('8000')
    host.to_enc['role::http_app']['ajp_port'].should eql('8009')
    host.to_enc['role::http_app']['sso_port'].should eql('8443')
  end

  host("e1-testapp2-001.mgmt.space.net.local") do |host|
    data = host.virtual_service.to_loadbalancer_config['e1-testapp2-vip.space.net.local']
    data['monitor_warn'].should eql(1)
    data['healthcheck_timeout'].should eql(10)
    data['env'].should eql('e1')
    data['app'].should eql('test_application')
    data['type'].should eql('http_and_sso_app')
    data['realservers']['blue'].should eql(["e1-testapp2-001.space.net.local", "e1-testapp2-002.space.net.local"])
    data['realservers']['green'].should be_nil

    host.to_enc['role::http_app']['port'].should eql('8000')
    host.to_enc['role::http_app']['ajp_port'].should be_nil
    host.to_enc['role::http_app']['sso_port'].should eql('8443')
  end
end
