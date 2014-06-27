require 'stacks/test_framework'

describe_stack 'analytics' do
  given do
    stack "analytics" do
      analyticsapp
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "analytics"
    end
  end

  host("e1-analyticsapp-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::analyticsapp_server' => {
    }})

    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"e1-analyticsapp-001.mgmt.space.net.local",
          :prod=>"e1-analyticsapp-001.space.net.local"},
        :availability_group=>"e1-analyticsapp",
        :networks=>[:mgmt, :prod],
        :hostname=>"e1-analyticsapp-001",
        :ram=>"2097152",
        :storage => {'/'.to_sym =>{:type=>"os", :size=>"3G"}},
        :domain=>"space.net.local"}])

  end
end
