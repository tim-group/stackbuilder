require 'stacks/environment'

describe 'Stacks::VirtualService' do
  before do
    extend Stacks::DSL
  end

  it 'provides the default vips when to_vip_spec is run' do
    stack "test" do
      virtual_appserver 'myvs'
    end

    env 'env', :primary_site => 'mars' do
      instantiate_stack 'test'
    end

    vip_spec = find('env-myvs-001.mgmt.mars.net.local').virtual_service.to_vip_spec
    vip_spec[:qualified_hostnames].should eql(:prod => 'env-myvs-vip.mars.net.local')
  end

  it 'provides the both front and prod vips when if enable_nat is turned on' do
    stack "test" do
      virtual_appserver 'myvs' do
        enable_nat
      end
    end

    env 'env', :primary_site => 'mars' do
      instantiate_stack 'test'
    end

    vip_spec = find('env-myvs-001.mgmt.mars.net.local').virtual_service.to_vip_spec
    vip_spec[:qualified_hostnames].should eql(:prod  => 'env-myvs-vip.mars.net.local',
                                              :front => 'env-myvs-vip.front.mars.net.local')
  end

  it 'allows a virtual service to add a vip on additional networks' do
    stack "test" do
      virtual_appserver 'myvs' do
        add_vip_network :mgmt
      end
    end

    env 'env', :primary_site => 'mars' do
      instantiate_stack 'test'
    end

    vip_spec = find('env-myvs-001.mgmt.mars.net.local').virtual_service.to_vip_spec
    vip_spec[:qualified_hostnames].should eql(:prod => 'env-myvs-vip.mars.net.local',
                                              :mgmt => 'env-myvs-vip.mgmt.mars.net.local')
  end
end
