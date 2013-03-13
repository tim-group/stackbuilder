require 'compute/controller'

describe Compute::Controller do

  before :each do
    @compute_node_client = double

    @dns_client = double
    @logger = double
    @dns_client.stub(:gethostbyname).and_return(nil)

    @compute_controller = Compute::Controller.new :compute_node_client => @compute_node_client, :dns_client => @dns_client, :logger=>@logger
  end

  it 'no hosts found' do
    @compute_node_client.stub(:find_hosts).and_return([])

    specs = [
      {:hostname => "vm1"},
      {:hostname => "vm2"}
    ]

    expect {
      @compute_controller.allocate(specs)
    }.to raise_error("unable to find any suitable compute nodes")
  end

  it 'allocates to the local fabric' do
    @compute_node_client.stub(:find_hosts).and_return([])

    specs = [{
      :hostname => "vm1",
      :fabric => "local"
    }, {
      :hostname => "vm2",
      :fabric => "local"
    }]

    localhost = `hostname --fqdn`.chomp

    @compute_controller.allocate(specs).should eql({localhost=>specs})
  end

  it 'allocates to a remote fabric' do
    @compute_node_client.stub(:find_hosts).with("st").and_return(["st-kvm-001.mgmt.st.net.local"])
    @compute_node_client.stub(:find_hosts).with("bs").and_return(["bs-kvm-001.mgmt.bs.net.local"])

    specs = [{
      :hostname => "vm1",
      :fabric => "st"
    }, {
      :hostname => "vm2",
      :fabric => "st"
    }, {
      :hostname => "vm3",
      :fabric => "bs"
    }]

    allocations = @compute_controller.allocate(specs)

    allocations.should eql({
      "st-kvm-001.mgmt.st.net.local" => [specs[0], specs[1]],
      "bs-kvm-001.mgmt.bs.net.local" => [specs[2]],
    })
  end

  it 'allocates by slicing specs' do
    @compute_node_client.stub(:find_hosts).with("st").and_return([
      "st-kvm-001.mgmt.st.net.local",
      "st-kvm-002.mgmt.st.net.local",
      "st-kvm-003.mgmt.st.net.local"
    ])
    @compute_node_client.stub(:find_hosts).with("bs").and_return([
      "bs-kvm-001.mgmt.bs.net.local",
      "bs-kvm-002.mgmt.bs.net.local"
    ])

    specs = [
      {:hostname => "vm0", :fabric => "st"},
      {:hostname => "vm1", :fabric => "st"},
      {:hostname => "vm2", :fabric => "st"},
      {:hostname => "vm3", :fabric => "st"},
      {:hostname => "vm4", :fabric => "st"},
      {:hostname => "vm5", :fabric => "bs"},
      {:hostname => "vm6", :fabric => "bs"},
      {:hostname => "vm7", :fabric => "bs"},
    ]

    allocations = @compute_controller.allocate(specs)

    allocations.should eql({
      "st-kvm-001.mgmt.st.net.local" => [specs[0],specs[3]],
      "st-kvm-002.mgmt.st.net.local" => [specs[1],specs[4]],
      "st-kvm-003.mgmt.st.net.local" => [specs[2]],
      "bs-kvm-001.mgmt.bs.net.local" => [specs[5],specs[7]],
      "bs-kvm-002.mgmt.bs.net.local" => [specs[6]],
    })
  end

  it 'launches the vms on the allocated hosts' do
    @compute_node_client.stub(:find_hosts).and_return(["myhost"])

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm1.mgmt.st.net.local"}
    }]

    @compute_node_client.stub(:launch).with("myhost", specs).and_return([["myhost", {"vm1" => "success"}]])
    @compute_node_client.should_receive(:launch).with("myhost", specs)

    @compute_controller.launch(specs)
  end

  it 'calls back when a launch is allocated' do
    @compute_node_client.stub(:find_hosts).and_return(["myhost"])

    specs = [{
      :hostname => "vm1",
      :qualified_hostnames => {"mgmt" => "vm1.mgmt.st.net.local"}
    }]

    @compute_node_client.stub(:launch)

    allocation = {}

    @compute_controller.launch(specs) do
      on :allocated do |vm, host|
        allocation[vm] = host
      end
    end

    allocation.should eql({'vm1' => 'myhost'})
  end

  it 'calls back if any launch command failed' do
    @compute_node_client.stub(:find_hosts).and_return(["myhost"])

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm1.mgmt.st.net.local"}
    }]

    @compute_node_client.stub(:launch).with("myhost", specs).and_return([["myhost", {"vm1" => "failed"}]])

    failure = false
    @compute_controller.launch(specs) do
      on :failure do |vm|
        failure = true
      end
    end

    failure.should eql(true)
  end

  it 'unaccounted for vms raise an error when launching' do
    @compute_node_client.stub(:find_hosts).and_return(["myhost"])

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm1.mgmt.st.net.local"}
    },{
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm2.mgmt.st.net.local"}
    }]

    @compute_node_client.stub(:launch).and_return([["myhost", {"vm1" => "success"}]])

    unaccounted = []
    @compute_controller.launch(specs) do
      on :unaccounted do |vm|
        unaccounted << vm
      end
    end

    unaccounted.should eql ["vm2"]
  end

  it 'will not launch if any machine already exists' do
    @dns_client.rspec_reset
    @dns_client.stub(:gethostbyname).with("vm1.mgmt.st.net.local").and_return(nil)
    @dns_client.stub(:gethostbyname).with("vm2.mgmt.st.net.local").and_return("1.2.3.4")

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm1.mgmt.st.net.local"}
    },{
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm2.mgmt.st.net.local"}
    }]

    expect {
      @compute_controller.launch(specs)
    }.to raise_error('some specified machines already exist: {"vm2.mgmt.st.net.local"=>"1.2.3.4"}')

    @compute_node_client.should_not_receive(:find_hosts)
    @compute_node_client.should_not_receive(:launch)
  end

  it 'will account foreach machine that is destroyed' do
    @dns_client.rspec_reset
    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm1.mgmt.st.net.local"}
    },{
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm2.mgmt.st.net.local"}
    }]

    @compute_node_client.stub(:clean).and_return([["host1", {"vm1" => "success"}], ["host2", {"vm2" => "success"}]])

    successful = []
    @compute_controller.clean(specs) do
      on :success do |vm|
        successful << vm
      end
    end

    successful.should eql(["vm1", "vm2"])
  end

  it 'unaccounted for vms (when clean is called) will be reported' do
    @dns_client.rspec_reset
    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm1.mgmt.st.net.local"}
    },{
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm2.mgmt.st.net.local"}
    }]

    @compute_node_client.stub(:clean).and_return([["myhost", {"vm1" => "success"}]])

    unaccounted = []
    @compute_controller.clean(specs) do
      on :unaccounted do |vm|
        unaccounted << vm
      end
    end

    unaccounted.should eql(["vm2"])
  end

  it 'will throw an exception if any nodes failed in the clean action ' do
    @dns_client.rspec_reset

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm1.mgmt.st.net.local"}
    },{
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => {"mgmt" => "vm2.mgmt.st.net.local"}
    }]

    failures = []
    @compute_node_client.stub(:clean).and_return([["host1", {"vm1" => "failed"}], ["host2", {"vm2" => "success"}]])
    @compute_controller.clean(specs) do
      on :failure do |vm|
        failures << vm
      end
    end

    failures.should eql [["vm1", "failed"]]
  end

end
