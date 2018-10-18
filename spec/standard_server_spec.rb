require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'standard' do
  given do
    stack "standard" do
      standard_service "mymachine"
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "standard"
    end
  end

  host("e1-mymachine-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['server']).to eql({})
  end
end

describe_stack 'standard with offset' do
  given do
    stack "standard" do
      standard_service "mymachine" do
        self.server_offset = 10
      end
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "standard"
    end
  end

  host("e1-mymachine-011.mgmt.space.net.local") do |host|
    expect(host.to_enc['server']).to eql({})
  end
end
