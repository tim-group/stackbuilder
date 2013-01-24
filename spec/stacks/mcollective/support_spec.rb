require 'stacks/mcollective/support'

describe Stacks::MCollective::Support do
  before do
    extend Stacks::MCollective::Support
    @mock_rpcclient = double
    class Stacks::MCollective::Support::MCollectiveRPC
      def self.rpcclient=(rpcclient)
        @@rpcclient = rpcclient
      end
      def rpcclient(name, options)
        return @@rpcclient
      end
    end
    Stacks::MCollective::Support::MCollectiveRPC.rpcclient=@mock_rpcclient

    def async_fork_and_return(&block)
      return Support::Forking::Future.new(&block)
    end
  end

  it 'shortcuts a nested new_client' do
    new_client("blah") do |mco|
      mco.should eql(@mock_rpcclient)
    end.value
  end

  it 'applies a filter so that only machines in the fabric are addressed' do
    @mock_rpcclient.should_receive(:fact_filter).with("domain", "mgmt.st.net.local")
    new_client("blah", :fabric=>"st") do |mco|
    end.value
  end

  it 'applies a filter so that only local machines are addressed' do
    @mock_rpcclient.should_receive(:identity_filter).with(`hostname --fqdn`.chomp)
    new_client("blah", :fabric=>"local") do |mco|
    end.value
  end
end
