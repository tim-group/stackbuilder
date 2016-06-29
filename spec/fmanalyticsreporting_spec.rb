require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'analytics' do
  given do
    stack "analytics" do
      fmanalyticsreporting_service
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "analytics"
    end
  end

  host("e1-fmanalyticsreporting-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::fmanalyticsreporting_server']).to eql({})
  end
end
