require 'stacks/test_framework'
describe_stack 'stack.virtual_ssoappserver.to_loadbalancer_config' do
  given do
    stack 'test' do
      virtual_ssoappserver 'testapp' do
        enable_ehcache
        self.application = 'test_application'
        self.instances = 2
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "test"
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
  end
end


