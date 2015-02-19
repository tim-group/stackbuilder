require 'stacks/test_framework'

describe_stack 'sensu' do
  given do
    stack "sensu" do
      sensu
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "sensu"
    end
  end

  host("e1-sensu-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql('role::sensu' => {
                             'server' => true
                           })
  end
end
