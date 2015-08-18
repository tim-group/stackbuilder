require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'quant' do
  given do
    stack "quant" do
      quantapp "quantapp" do
        allow_host '0.0.0.0'
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "quant"
    end
  end

  host("e1-quantapp-001.mgmt.space.net.local") do |host|
    enc = host.to_enc
    enc['role::quantapp_server']['allowed_hosts'].should eql(['0.0.0.0'])
    enc['role::quantapp_server']['environment'].should eql('e1')
    host.to_specs.shift[:ram].should eql('2097152')
  end
end
