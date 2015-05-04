# rubocop:disable Style/ClassVars

describe Support::MCollective do
  before do
    extend Support::MCollective
    ENV['FACTERLIB'] = "/var/lib/puppet/lib/facter:/var/lib/puppet/facts"
    @mock_rpcclient = double
    class Support::MCollective::MCollectiveRPC
      def self.mco_options
        @@mco_options
      end

      def self.rpcclient=(rpcclient)
        @@rpcclient = rpcclient
      end

      def rpcclient(_name, options)
        @@mco_options = options
        @@rpcclient
      end
    end
    Support::MCollective::MCollectiveRPC.rpcclient = @mock_rpcclient

    def async_fork_and_return(&block)
      Support::Forking::Future.new(&block)
    end

    @mock_rpcclient.should_receive(:disconnect)
  end

  it 'shortcuts a nested mco_client' do
    @mock_rpcclient.should_receive(:discover).with(no_args)
    mco_client("blah") do |mco|
      mco.should eql(@mock_rpcclient)
    end
  end

  it 'applies a filter so that only machines in the fabric are addressed' do
    @mock_rpcclient.should_receive(:discover).with(no_args)
    @mock_rpcclient.should_receive(:fact_filter).with("domain", "mgmt.st.net.local")
    mco_client("blah", :fabric => "st")
  end

  # XXX Facter is slow
  it 'applies a filter so that only local machines are addressed' do
    @mock_rpcclient.should_receive(:discover).with(no_args).ordered
    @mock_rpcclient.should_receive(:fact_filter).with("owner", Facter.value('owner'))
    mco_client("blah", :fabric => "local")
  end

  # XXX Facter is slow
  it 'uses a timeout if supplied' do
    @mock_rpcclient.should_receive(:discover).with(no_args).ordered
    @mock_rpcclient.should_receive(:fact_filter).with("owner", Facter.value('owner'))
    mco_client("blah", :fabric => "local", :timeout => 44)
    Support::MCollective::MCollectiveRPC.mco_options[:options][:timeout].should eql(44)
  end

  it 'can be pre-injected with a list of hosts to discover' do
    my_nodes = %w(1 2 3)
    @mock_rpcclient.should_receive(:discover).with(:nodes => my_nodes)
    mco_client("blah", :nodes => my_nodes)
  end

  it 'switch the mco key to use' do
    @mock_rpcclient.should_receive(:discover).with(no_args).ordered
    mco_client("blah") do
    end
  end
end
