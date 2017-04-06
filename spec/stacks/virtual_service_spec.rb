require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe 'Stacks::Services::VirtualService' do
  describe_stack 'provides the default vips when to_vip_spec is run' do
    given do
      stack "test" do
        app_service 'myvs'
      end

      env 'env', :primary_site => 'mars' do
        instantiate_stack 'test'
      end
    end

    host('env-myvs-001.mgmt.mars.net.local') do |host|
      vip_spec = host.virtual_service.to_vip_spec(:primary_site)
      expect(vip_spec[:qualified_hostnames]).to eql(:prod => 'env-myvs-vip.mars.net.local')
    end
  end

  describe_stack 'provides the both front and prod vips when dnat_enabled' do
    given do
      stack "test" do
        app_service 'myvs' do
          nat_config.dnat_enabled = true
        end
      end

      env 'env', :primary_site => 'mars' do
        instantiate_stack 'test'
      end
    end

    host('env-myvs-001.mgmt.mars.net.local') do |host|
      vip_spec = host.virtual_service.to_vip_spec(:primary_site)
      expect(vip_spec[:qualified_hostnames]).to eql(
        :prod  => 'env-myvs-vip.mars.net.local',
        :front => 'env-myvs-vip.front.mars.net.local'
      )
    end
  end

  describe_stack 'allows a virtual service to add a vip on additional networks' do
    given do
      stack "test" do
        app_service 'myvs' do
          add_vip_network :mgmt
        end
      end

      env 'env', :primary_site => 'mars' do
        instantiate_stack 'test'
      end
    end

    host('env-myvs-001.mgmt.mars.net.local') do |host|
      vip_spec = host.virtual_service.to_vip_spec(:primary_site)
      expect(vip_spec[:qualified_hostnames]).to eql(
        :prod => 'env-myvs-vip.mars.net.local',
        :mgmt => 'env-myvs-vip.mgmt.mars.net.local'
      )
    end
  end

  describe_stack 'allows a vip warning and critical levels to be manipulated' do
    given do
      stack "test" do
        loadbalancer_service
        app_service 'app' do
          self.instances = 4
          self.vip_warning_members = 0  if %w(latest).include? environment.name
          self.vip_critical_members = 1 if %w(production).include? environment.name
        end
      end

      env 'latest', :primary_site => 'mars' do
        instantiate_stack 'test'
      end
      env 'production', :primary_site => 'twix' do
        instantiate_stack 'test'
      end
    end

    host("latest-lb-001.mgmt.mars.net.local") do |host|
      vs = host.to_enc['role::loadbalancer']['virtual_servers']
      expect(vs.keys).to include('latest-app-vip.mars.net.local')
      expect(vs['latest-app-vip.mars.net.local']['monitor_warn']).to eql(0)
      expect(vs['latest-app-vip.mars.net.local']['monitor_critical']).to eql(0) # default
    end

    host("production-lb-001.mgmt.twix.net.local") do |host|
      vs = host.to_enc['role::loadbalancer']['virtual_servers']
      expect(vs.keys).to include('production-app-vip.twix.net.local')
      expect(vs['production-app-vip.twix.net.local']['monitor_warn']).to eql(1) # default
      expect(vs['production-app-vip.twix.net.local']['monitor_critical']).to eql(1)
    end
  end
end
