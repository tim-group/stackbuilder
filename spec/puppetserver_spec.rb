require 'stackbuilder/stacks/factory'
require 'stacks/test_framework'

describe_stack 'basic dev puppetmaster' do
  given do
    stack 'puppetserver' do
      puppetserver 'basic'
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "puppetserver"
    end
  end

  host("e1-basic-001.mgmt.space.net.local") do |host|
    expect(host.to_enc).to eql({})
    expect(host.to_specs.first[:template]).to eql('puppetserver')
    expect(host.to_specs.first[:cnames]).to eql(:mgmt => {
                                                  "puppet" => "e1-basic-001.mgmt.space.net.local"
                                                })
  end
end

describe_stack 'basic dev puppetserver without cname' do
  given do
    stack 'puppetserver' do
      puppetserver 'pm' do
        @instances = 1
        each_machine do |machine|
          machine.cnames = {}
        end
      end
    end
    env "e1", :primary_site => "space" do
      instantiate_stack "puppetserver"
    end
  end

  it_stack 'puppetserver should have the correct enc data' do
    host("e1-pm-001.mgmt.space.net.local") do |host|
      expect(host.to_enc).to eql({})
      expect(host.to_specs.first[:template]).to eql('puppetserver')
      expect(host.to_specs.first[:cnames]).to eql({})
    end
  end

  it_stack 'should contain 1 puppetserver' do |stack|
    expect(stack).to have_host('e1-pm-001.mgmt.space.net.local')
    expect(stack).not_to have_host('e1-pm-002.mgmt.space.net.local')
  end
end
