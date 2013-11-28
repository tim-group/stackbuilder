require 'stacks/test_framework'
describe_stack 'jenkins' do
  given do
    stack "jenkins" do
      cislave 'jenkinsslave' do
        each_machine do |machine|
          machine.vcpus = '8'
          machine.image_size = '10G'
          machine.ram = '8000'
        end
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "jenkins"
    end
  end

  host("e1-jenkinsslave-002.mgmt.space.net.local") do |host|
    host.should have_ancestory(
      ["e1","jenkins", "jenkinsslave", "jenkinsslave-002"])

      host.to_spec.should eql({
        :fabric=>"space",
        :vcpus =>"8",
        :image_size =>"10G",
        :qualified_hostnames=>{
        :mgmt=>"e1-jenkinsslave-002.mgmt.space.net.local",
        :prod=>"e1-jenkinsslave-002.space.net.local",
        :front=>"e1-jenkinsslave-002.front.space.net.local"},
        :group=>"e1-jenkinsslave",
        :networks=>[:mgmt, :prod, :front],
        :hostname=>"e1-jenkinsslave-002",
        :ram=>"8000",
        :domain=>"space.net.local"})
  end

end


