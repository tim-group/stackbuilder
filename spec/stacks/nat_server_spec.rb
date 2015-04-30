require 'stacks/environment'
require 'stacks/test_framework'

describe_stack 'nat servers should have all 3 networks' do
  given do
    stack 'fabric' do
      natserver
    end

    env "oy", :primary_site => "oy" do
      instantiate_stack 'fabric'
    end
  end

  it_stack 'should contain all the expected hosts' do |stack|
    stack.should have_hosts(
      [
        'oy-nat-001.mgmt.oy.net.local',
        'oy-nat-002.mgmt.oy.net.local'
      ]
    )
  end

  host("oy-nat-001.mgmt.oy.net.local") do |host|
    host.to_specs.first[:networks].should eql([:mgmt, :prod, :front])
  end
end
