
require 'compute/controller'

describe Compute::Controller do

  it 'allocates every spec to a host' do
    compute_node_client = double
    compute_node_client.stub(:find_hosts).and_return(["host1"])

    compute_controller = Compute::Controller.new :compute_node_client=>compute_node_client

    specs = [
      {:hostname=>"vm1"},
      {:hostname=>"vm2"}
    ]

    allocations = compute_controller.allocate(specs)

    allocations.should eql({
        "vm1"=>"host1",
        "vm2"=>"host1"
    })

  end

  it 'no hosts found' do
    compute_node_client = double
    compute_node_client.stub(:find_hosts).and_return([])

    compute_controller = Compute::Controller.new :compute_node_client=>compute_node_client

    specs = [
      {:hostname=>"vm1"},
      {:hostname=>"vm2"}
    ]

    expect {
      compute_controller.allocate(specs)
    }.to raise_error("unable to find any suitable compute nodes")

  end

  it 'allocates to the local fabric'

  it 'allocates to a remote fabric'

end
