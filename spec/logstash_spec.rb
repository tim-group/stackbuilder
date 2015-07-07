require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'logstash' do
  given do
    stack "logstash" do
      logstash
    end

    env "e1", :primary_site => "space" do
      instantiate_stack "logstash"
    end
  end

  host("e1-logstash-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql('role::logstash_server' => {
                             'environment' => "e1",
                           })
  end
end
