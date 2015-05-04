describe 'Stacks::Services::VirtualService' do
  describe_stack 'provides the default vips when to_vip_spec is run' do
    given do
      stack "test" do
        virtual_appserver 'myvs'
      end

      env 'env', :primary_site => 'mars' do
        instantiate_stack 'test'
      end
    end

    host('env-myvs-001.mgmt.mars.net.local') do |host|
      vip_spec = host.virtual_service.to_vip_spec(:primary_site)
      vip_spec[:qualified_hostnames].should eql(:prod => 'env-myvs-vip.mars.net.local')
    end
  end

  describe_stack 'provides the both front and prod vips when if enable_nat is turned on' do
    given do
      stack "test" do
        virtual_appserver 'myvs' do
          enable_nat
        end
      end

      env 'env', :primary_site => 'mars' do
        instantiate_stack 'test'
      end
    end

    host('env-myvs-001.mgmt.mars.net.local') do |host|
      vip_spec = host.virtual_service.to_vip_spec(:primary_site)
      vip_spec[:qualified_hostnames].should eql(
        :prod  => 'env-myvs-vip.mars.net.local',
        :front => 'env-myvs-vip.front.mars.net.local'
      )
    end
  end

  describe_stack 'allows a virtual service to add a vip on additional networks' do
    given do
      stack "test" do
        virtual_appserver 'myvs' do
          add_vip_network :mgmt
        end
      end

      env 'env', :primary_site => 'mars' do
        instantiate_stack 'test'
      end
    end

    host('env-myvs-001.mgmt.mars.net.local') do |host|
      vip_spec = host.virtual_service.to_vip_spec(:primary_site)
      vip_spec[:qualified_hostnames].should eql(
        :prod => 'env-myvs-vip.mars.net.local',
        :mgmt => 'env-myvs-vip.mgmt.mars.net.local'
      )
    end
  end
end
