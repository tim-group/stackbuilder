
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

  it 'allocates by slicing specs' do
    compute_node_client = double
    compute_node_client.stub(:find_hosts).with("st").and_return(
      ["st-kvm-001.mgmt.st.net.local","st-kvm-002.mgmt.st.net.local","st-kvm-003.mgmt.st.net.local"]
    )
    compute_node_client.stub(:find_hosts).with("bs").and_return(
      ["bs-kvm-001.mgmt.bs.net.local", "bs-kvm-002.mgmt.bs.net.local"]
    )

    compute_controller = Compute::Controller.new :compute_node_client=>compute_node_client

    specs = [
      {:hostname=>"vm0",:fabric=>"st"},
      {:hostname=>"vm1",:fabric=>"st"},
      {:hostname=>"vm2",:fabric=>"st"},
      {:hostname=>"vm3",:fabric=>"st"},
      {:hostname=>"vm4",:fabric=>"st"},
      {:hostname=>"vm5",:fabric=>"bs"},
      {:hostname=>"vm6",:fabric=>"bs"},
      {:hostname=>"vm7",:fabric=>"bs"},
    ]

    allocations = compute_controller.allocate(specs)

    allocations.should eql({
      "st-kvm-001.mgmt.st.net.local"=> [specs[0],specs[3]],
      "st-kvm-002.mgmt.st.net.local"=> [specs[1],specs[4]],
      "st-kvm-003.mgmt.st.net.local"=> [specs[2]],
      "bs-kvm-001.mgmt.bs.net.local"=> [specs[5],specs[7]],
      "bs-kvm-002.mgmt.bs.net.local"=> [specs[6]],
    })

  end

  it 'launches the vms on the allocated hosts' do
    compute_node_client = double
    compute_node_client.stub(:find_hosts).and_return(["myhost"])

    compute_controller = Compute::Controller.new :compute_node_client=>compute_node_client

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => "vm1.mgmt.st.net.local"
      }]

    compute_node_client.should_receive(:launch).with("myhost", specs)

    compute_controller.launch(specs)
  end

end
