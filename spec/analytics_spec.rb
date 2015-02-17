require 'stacks/test_framework'

describe_stack 'analytics' do
  given do
    stack "analytics" do
      analyticsapp
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "analytics"
    end
  end

  host("e1-analyticsapp-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
                             'role::analyticsapp_server' => {
                               'datadir'     => false,
                               'environment' => 'e1'
                             }
                           })
  end
end
