require 'stacks/test_framework'
describe_stack 'lb' do
  given do
    stack "lb" do
      loadbalancer  do
      end
    end

    env "e1", :primary_site=>"space", :lb_virtual_router_id=>66 do
      instantiate_stack "lb"
    end
  end

  host("e1-lb-002.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::loadbalancer'=> {
        'virtual_router_id' => 66,
        'virtual_servers' => {}
      }
    })
    host.to_specs.shift[:qualified_hostnames].should eql({
      :mgmt=>"e1-lb-002.mgmt.space.net.local",
      :prod=>"e1-lb-002.space.net.local",
    })
    host.to_specs.shift[:availability_group].should eql('e1-lb')
    host.to_specs.shift[:networks].should eql([:mgmt, :prod])
    host.to_specs.shift[:hostname].should eql('e1-lb-002')
    host.to_specs.shift[:domain].should eql('space.net.local')
  end

end


