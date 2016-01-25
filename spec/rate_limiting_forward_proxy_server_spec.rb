require 'matchers/server_matcher'
require 'stackbuilder/stacks/factory'

describe_stack 'rate limiting forward proxy' do
  describe_stack 'default' do
    given do
      stack 'mystack' do
        rate_limited_forward_proxy 's3proxy'
      end

      env 'e1', :primary_site => 'space' do
        instantiate_stack 'mystack'
      end
    end

    host('e1-s3proxy-001.mgmt.space.net.local') do |host|
      expect(host.to_enc).to eql('role::rate_limited_forward_proxy' => { 'tc_rate' => '8Mbit' })
      expect(host.networks).to eql([:mgmt, :prod])
    end
  end

  describe_stack 'with custom traffic control rate' do
    given do
      stack 'mystack' do
        rate_limited_forward_proxy 's3proxy' do
          each_machine do |machine|
            machine.tc_rate = '42jigawatts'
          end
        end
      end

      env 'e2', :primary_site => 'space' do
        instantiate_stack 'mystack'
      end
    end

    host('e2-s3proxy-001.mgmt.space.net.local') do |host|
      expect(host.to_enc).to eql('role::rate_limited_forward_proxy' => { 'tc_rate' => '42jigawatts' })
    end
  end
end
