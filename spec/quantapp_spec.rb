require 'stacks/factory'
require 'stacks/test_framework'

describe_stack 'quant' do
  given do
    stack "quant" do
      quantapp "quantapp" do
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "quant"
    end
  end

  host("e1-quantapp-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql('role::quantapp_server' => {
                           })
    host.to_specs.shift[:ram].should eql('2097152')
  end
end
