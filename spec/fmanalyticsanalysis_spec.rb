require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'analytics' do
  given do
    stack "analytics" do
      fmanalyticsanalysis_service
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "analytics"
    end
  end

  host("e1-fmanalyticsanalysis-001.mgmt.space.net.local") do |host|
    expect(host.to_enc['role::fmanalyticsanalysis_server']).to eql('datadir'     => false,
                                                                   'environment' => 'e1')
    expect(host.to_enc['role::shiny_server']).to eql({})
  end
end
