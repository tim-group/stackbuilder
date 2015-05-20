require 'stacks/factory'
require 'stacks/test_framework'

describe_stack 'analytics' do
  given do
    stack "analytics" do
      fmanalyticsanalysis
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "analytics"
    end
  end

  host("e1-fmanalyticsanalysis-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql('role::fmanalyticsanalysis_server' => {
                             'datadir'     => false,
                             'environment' => 'e1'
                           })
  end
end
