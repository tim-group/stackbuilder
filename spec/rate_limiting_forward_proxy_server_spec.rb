require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'

describe_stack 'rate limiting forward proxy' do

  describe_stack 'default' do
    given do
      stack 'mystack' do
        rate_limited_forward_proxy 's3proxy'
      end
  
      env 'testing', :primary_site => 'space' do
        instantiate_stack 'mystack'
      end
    end
  
    host('testing-s3proxy-001.mgmt.space.net.local') do |host|
      expect(host.to_enc).to eql('role::rate_limited_forward_proxy' => {})
  
      expect(host.networks).to eql([:mgmt, :prod])
    end
  end
end
