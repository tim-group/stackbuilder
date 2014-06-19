require 'stacks/test_framework'

describe_stack 'logstash' do
  given do
    stack "logstash" do
      logstash
    end

    env "e1", :primary_site=>"space" do
      instantiate_stack "logstash"
    end
  end

  host("e1-logstash-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({
      'role::logstash_server' => {
        'environment' => "e1"
      }})

    host.to_specs.should eql([
      {:fabric=>"space",
       :qualified_hostnames=>{
          :mgmt=>"e1-logstash-001.mgmt.space.net.local",
          :prod=>"e1-logstash-001.space.net.local"},
        :availability_group=>"e1-logstash",
        :networks=>[:mgmt, :prod],
        :hostname=>"e1-logstash-001",
        :ram=>"2097152",
        :storage => {'/'.to_sym =>{:type=>"os", :size=>"3G"}},
        :domain=>"space.net.local"}])

  end
end
