require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'standard' do
  given do
    stack "standard" do
      standard "mymachine"
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "standard"
    end
  end

  host("e1-mymachine-001.mgmt.space.net.local") do |host|
    expect(host.to_enc).to eql('server::default_new_mgmt_net_local' => {})
  end
end
