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
end
