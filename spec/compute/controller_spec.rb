
require 'compute/controller'

describe Compute::Controller do

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

  it 'allocates to the local fabric' do

    compute_node_client = double
    compute_node_client.stub(:find_hosts).and_return([])
    compute_controller = Compute::Controller.new :compute_node_client=>compute_node_client

    specs = [
      {
      :hostname=>"vm1",
      :fabric=>"local"
    },
      {
      :hostname=>"vm2",
      :fabric => "local"
    }
    ]

    localhost = `hostname --fqdn`.chomp

    compute_controller.allocate(specs).should eql(
      {localhost=>specs})
  end

  it 'allocates to a remote fabric' do
    compute_node_client = double
    compute_node_client.stub(:find_hosts).with("st").and_return(["st-kvm-001.mgmt.st.net.local"])

    compute_node_client.stub(:find_hosts).with("bs").and_return(["bs-kvm-001.mgmt.bs.net.local"])

    compute_controller = Compute::Controller.new :compute_node_client=>compute_node_client

    specs = [
      {
        :hostname=>"vm1",
        :fabric=>"st"
      },
      {
        :hostname=>"vm2",
        :fabric => "st"
      },
      {
        :hostname=>"vm3",
        :fabric=>"bs"
      },
    ]

    allocations = compute_controller.allocate(specs)

    allocations.should eql({
      "st-kvm-001.mgmt.st.net.local"=> [specs[0], specs[1]],
      "bs-kvm-001.mgmt.bs.net.local"=> [specs[2]],
    })

  end

  it 'launches the vms on the allocated hosts' do
    compute_node_client = double
    compute_node_client.stub(:find_hosts).and_return(["myhost"])

    compute_controller = Compute::Controller.new :compute_node_client=>compute_node_client

    specs = [{
        :hostname=>"vm1",
        :fabric=>"st"
      }]


    compute_node_client.should_receive(:launch).with("myhost", specs)

    compute_controller.launch(specs)

  end

end
