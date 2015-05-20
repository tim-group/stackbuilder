require 'stacks/factory'
require 'stacks/test_framework'

describe_stack 'basic dev puppetmaster' do
  given do
    stack 'puppetmaster' do
      puppetmaster 'basic'
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "puppetmaster"
    end
  end

  host("e1-basic-001.mgmt.space.net.local") do |host|
    host.to_enc.should eql({})
    host.to_specs.first[:template].should eql('puppetmaster')
    host.to_specs.first[:cnames].should eql(:mgmt => {
                                              "puppet" => "e1-basic-001.mgmt.space.net.local"
                                            })
  end
end

describe_stack 'basic dev puppetmaster without cname' do
  given do
    stack 'puppetmaster' do
      puppetmaster 'pm' do
        @instances = 1
        each_machine do |machine|
          machine.cnames = {}
        end
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "puppetmaster"
    end
  end

  it_stack 'puppetmaster should have the correct enc data' do
    host("e1-pm-001.mgmt.space.net.local") do |host|
      host.to_enc.should eql({})
      host.to_specs.first[:template].should eql('puppetmaster')
      host.to_specs.first[:cnames].should eql({})
    end
  end

  it_stack 'should contain 1 puppetmaster' do |stack|
    stack.should have_host('e1-pm-001.mgmt.space.net.local')
    stack.should_not have_host('e1-pm-002.mgmt.space.net.local')
  end
end
