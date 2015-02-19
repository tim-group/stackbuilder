require 'stacks/test_framework'
describe_stack 'jenkins' do
  given do
    stack "jenkins" do
      cislave 'jenkinsslave' do
        each_machine do |machine|
          machine.vcpus = '8'
          machine.modify_storage('/'.to_sym => { :size => '10G' })
          machine.ram = '8000'
        end
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "jenkins"
    end
  end

  host("e1-jenkinsslave-002.mgmt.space.net.local") do |host|
    host.should have_ancestory(
      ["e1", "jenkins", "jenkinsslave", "jenkinsslave-002"])

    host.to_enc.should eql('role::cinode_precise' => {})
  end
end
