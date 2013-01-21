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
    mcollective_fabric(:broker=>"dev-puppet", :timeout=>4) do
      provision_vms([])
    end
  end

  it 'throws an exception it a mistake was made' do
    expect do
      mcollective_fabric(:broker=>"dev-puppet", :timeout=>4) do
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
end
