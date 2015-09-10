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
    expect(enc['role::quantapp_server']['allowed_hosts']).to eql(['0.0.0.0'])
    expect(enc['role::quantapp_server']['environment']).to eql('e1')
    expect(host.to_specs.shift[:ram]).to eql('2097152')
  end
end
