require 'stacks/test_framework'

describe_stack 'standard' do
  given do
    stack "standard" do
      standard "mymachine"
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "standard"
    end
  end

  host("e1-mymachine-001.mgmt.space.net.local") do |host|
    host.to_enc

    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"e1-mymachine-001.mgmt.space.net.local",
          :prod=>"e1-mymachine-001.space.net.local"},
        :availability_group => "e1-mymachine",
        :networks=>[:mgmt, :prod],
        :hostname=>"e1-mymachine-001",
        :domain=>"space.net.local",
        :storage => {'/'.to_sym => {:type=>"os", :size=>"3G"}},
        :ram => "2097152"}])
  end
end
