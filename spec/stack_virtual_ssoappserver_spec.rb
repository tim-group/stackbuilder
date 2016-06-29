require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'stack.app_service.to_loadbalancer_config for sso' do
  given do
    stack 'test' do
      app_service 'testapp' do
        enable_ehcache
        enable_sso('8443')
        enable_ajp('8009')
        disable_http_lb_hack
        self.application = 'test_application'
        self.instances = 2
      end
    end

    stack 'test_stack_2' do
      app_service 'testapp2' do
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
    data = host.virtual_service.to_loadbalancer_config(:primary_site, 'space')['e1-testapp-vip.space.net.local']
    expect(data['monitor_warn']).to eql(1)
    expect(data['healthcheck_timeout']).to eql(10)
    expect(data['env']).to eql('e1')
    expect(data['app']).to eql('test_application')
    expect(data['type']).to eql('sso_app')
    expect(data['realservers']['blue']).to eql(["e1-testapp-001.space.net.local", "e1-testapp-002.space.net.local"])
    expect(data['realservers']['green']).to be_nil

    expect(host.to_enc['role::http_app']['port']).to eql('8000')
    expect(host.to_enc['role::http_app']['ajp_port']).to eql('8009')
    expect(host.to_enc['role::http_app']['sso_port']).to eql('8443')
  end

  host("e1-testapp2-001.mgmt.space.net.local") do |host|
    data = host.virtual_service.to_loadbalancer_config(:primary_site, 'space')['e1-testapp2-vip.space.net.local']
    expect(data['monitor_warn']).to eql(1)
    expect(data['healthcheck_timeout']).to eql(10)
    expect(data['env']).to eql('e1')
    expect(data['app']).to eql('test_application')
    expect(data['type']).to eql('http_and_sso_app')
    expect(data['realservers']['blue']).to eql(["e1-testapp2-001.space.net.local", "e1-testapp2-002.space.net.local"])
    expect(data['realservers']['green']).to be_nil

    expect(host.to_enc['role::http_app']['port']).to eql('8000')
    expect(host.to_enc['role::http_app']['ajp_port']).to be_nil
    expect(host.to_enc['role::http_app']['sso_port']).to eql('8443')
  end
end
