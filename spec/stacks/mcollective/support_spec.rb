require 'stacks/mcollective/support'

describe Stacks::MCollective::Support do
  before do
    extend Stacks::MCollective::Support
    @runner = double()
    def create_fabric_runner(options)
      return @runner
    end
  end

  it 'shortcuts a nested new_client' do
    mock_client = double
    mock_client.stub(:do_cool_stuff).and_return("yehah")
    @runner.stub(:new_client).and_return(mock_client)
    result = new_client(:fabric=>"st",
                           :timeout=>5) do |mco|
      mco.do_cool_stuff.should eql("yehah")
      []
    end.value.should eql([])
  end

  it 'sets an mcollective agent with appropriate params' do
    @runner.stub(:provision_vms).and_return([])
    result = mcollective_fabric(:fabric=>"st",
                                :timeout=>5) do |runner|
      result = runner.provision_vms([])
      result
    end.should eql([])
  end

  it 'applies a filter so that only machines in the fabric are addressed' do
    fork do
      mock_rpcclient = double()
      class Stacks::MCollective::Support::MCollectiveRPC
        def self.rpcclient=(rpcclient)
         @@rpcclient = rpcclient
        end

        def rpcclient(name,options)
          @@rpcclient
        end
      end

      Stacks::MCollective::Support::MCollectiveRPC.rpcclient=mock_rpcclient
      mock_rpcclient.should_receive(:fact_filter).with("domain", "mgmt.st.net.local")
      runner = Stacks::MCollective::Support::MCollectiveFabricRunner.new({:fabric=>"st"})
      runner.new_client("blah") do |mco|
      end
    end
  end

  it 'applies a filter so that only local machines are addressed' do
    fork do
      mock_rpcclient = double()
      class Stacks::MCollective::Support::MCollectiveRPC
        def self.rpcclient=(rpcclient)
         @@rpcclient = rpcclient
        end

        def rpcclient(name,options)
          @@rpcclient
        end
      end

      Stacks::MCollective::Support::MCollectiveRPC.rpcclient=mock_rpcclient
      mock_rpcclient.should_receive(:identity_filter).with(`hostname --fqdn`.chomp)
      runner = Stacks::MCollective::Support::MCollectiveFabricRunner.new({:fabric=>"local"})
      runner.new_client("blah") do |mco|
        mco.should eql(mock_rpcclient)
      end
    end
  end
end
