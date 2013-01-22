require 'stacks/mcollective/support'

describe Stacks::MCollective::Support do
  before do
    extend Stacks::MCollective::Support
    @runner = double()
    def create_fabric_runner(options)
      return @runner
    end
  end

  it 'sets an mcollective agent with appropriate params' do
    @runner.stub(:provision_vms).and_return([])
    result = mcollective_fabric(:fabric=>"st",
                                :timeout=>5) do |runner|
      result = runner.provision_vms([])
      result
    end.should eql([])
  end

  it 'returns multiple futures for async execs' do
    future1 = async_mcollective_fabric do |runner|
      4.times do
        puts "A"
      end
      1
    end

    future2 = async_mcollective_fabric do |runner|
      4.times do
        puts "B"
      end
      2
    end

    future1.value.should eql(1)
    future2.value.should eql(2)
  end

  it 'throws an exception it a mistake was made' do
    expect do
      mcollective_fabric(:broker=>"dev-puppet", :timeout=>4).value do
        provisio
      end
    end.to raise_error
  end

  it 'throws an exception it a mistake was made' do
    @runner.stub(:provision_vms).and_return([])
    expect do
      mcollective_fabric(:broker=>"dev-puppet", :timeout=>4) do
        provisio
      end
    end.to raise_error
  end

  it 'applies a filter so that only machines in the fabric are addressed' do
    fork do
      mock_rpcclient = double()
      class Stacks::MCollective::Support::MCollectiveFabricRunner
        def self.rpcclient=(rpcclient)
         @@rpcclient = rpcclient
       end

       def rpcclient(name,options)
        @@rpcclient
       end
      end

      Stacks::MCollective::Support::MCollectiveFabricRunner.rpcclient=mock_rpcclient
      mock_rpcclient.should_receive(:fact_filter).with("domain", "mgmt.st.net.local")
      runner = Stacks::MCollective::Support::MCollectiveFabricRunner.new({:fabric=>"st"})
      runner.new_client("blah") do |mco|
      end
    end
  end

  it 'applies a filter so that only local machines are addressed' do
    fork do
      mock_rpcclient = double()
      class Stacks::MCollective::Support::MCollectiveFabricRunner
        def self.rpcclient=(rpcclient)
          @@rpcclient = rpcclient
        end

        def rpcclient(name,options)
          @@rpcclient
        end
      end

      Stacks::MCollective::Support::MCollectiveFabricRunner.rpcclient=mock_rpcclient
      mock_rpcclient.should_receive(:identity_filter).with(`hostname --fqdn`.chomp)
      runner = Stacks::MCollective::Support::MCollectiveFabricRunner.new({:fabric=>"local"})
      runner.new_client("blah") do |mco|
      end
    end
  end
end
