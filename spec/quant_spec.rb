require 'stacks/test_framework'

describe_stack 'quant' do
  given do
    stack "quant" do
      quantapp "quantapp" do
      end
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "quant"
    end
  end

  host("e1-quantapp-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::quantapp_server' => {
      }})

    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"e1-quantapp-001.mgmt.space.net.local",
          :prod=>"e1-quantapp-001.space.net.local"},
        :group=>"e1-quantapp",
        :networks=>[:mgmt, :prod],
        :hostname=>"e1-quantapp-001",
        :ram=>"4194304",
        :domain=>"space.net.local"}])

  end
end
