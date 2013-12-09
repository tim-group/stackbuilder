require 'stacks/test_framework'

describe_stack 'standard' do
  given do
    stack "standard" do
      standard "mymachine-001"
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "standard"
    end
  end

  host("e1-mymachine-001.mgmt.space.net.local") do |host|
    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"e1-mymachine-001.mgmt.space.net.local",
          :prod=>"e1-mymachine-001.space.net.local"},
        :availability_group => nil,
        :networks=>[:mgmt, :prod],
        :hostname=>"e1-mymachine-001",
        :domain=>"space.net.local",
        :ram => "2097152"}])
  end
end
