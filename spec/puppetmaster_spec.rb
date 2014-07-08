require 'stacks/test_framework'

describe_stack 'puppetmaster' do
  given do
    stack 'puppetmaster' do
      puppetmaster
    end
    env "e1", { :primary_site=>"space" } do
      instantiate_stack "puppetmaster"
    end
  end

  host("e1-puppetmaster-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql ({
      'role::dev_puppetmaster' => {}
    })
    host.to_specs.first[:template].should eql('puppetmaster')
    host.to_specs.first[:cnames].should eql({
      :mgmt=>{
        "puppet"=>"e1-puppetmaster-001.mgmt.space.net.local"
      }
    })

  end

end
