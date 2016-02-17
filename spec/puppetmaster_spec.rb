require 'stackbuilder/stacks/factory'
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
    expect(host.to_enc).to eql({})
    expect(host.to_specs.first[:template]).to eql('puppetmaster')
    expect(host.to_specs.first[:cnames]).to eql(:mgmt => {
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

  host("e1-pm-001.mgmt.space.net.local") do |host|
    expect(host.to_enc).to eql({})
    expect(host.to_specs.first[:template]).to eql('puppetmaster')
    expect(host.to_specs.first[:cnames]).to eql({})
  end

  it_stack 'should contain 1 puppetmaster' do |stack|
    expect(stack).to have_host('e1-pm-001.mgmt.space.net.local')
    expect(stack).not_to have_host('e1-pm-002.mgmt.space.net.local')
  end
end
