require 'stacks/test_framework'
describe_stack 'lb' do
  given do
    stack "lb" do
      loadbalancer  do
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "lb"
    end
  end

  host("e1-lb-002.mgmt.space.net.local") do |host|
    host.to_spec.should eql({
      :fabric=>"space",
      :qualified_hostnames=>{
      :mgmt=>"e1-lb-002.mgmt.space.net.local",
      :prod=>"e1-lb-002.space.net.local"},
      :availability_group=>"e1-lb",
      :networks=>[:mgmt, :prod],
      :hostname=>"e1-lb-002",
      :ram=>"2097152",
      :storage => {'/'.to_sym =>{:type=>"os", :size=>"3G"}},
      :domain=>"space.net.local"})
  end

end


