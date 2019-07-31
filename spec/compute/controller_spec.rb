require 'stackbuilder/stacks/factory'

describe Compute::Controller do
  before :each do
    @compute_node_client = double
    @compute_controller = Compute::Controller.new :compute_node_client => @compute_node_client
  end

  it 'no hosts found' do
    allow(@compute_node_client).to receive(:audit_fabric).and_return({})

    specs = [
      { :hostname => "vm1" },
      { :hostname => "vm2" }
    ]

    expect do
      @compute_controller.allocate(specs)
    end.to raise_error("unable to find any suitable compute nodes")
  end

  it 'allocates to the local fabric' do
    allow(@compute_node_client).to receive(:audit_fabric).and_return([])

    specs = [{
      :hostname => "vm1",
      :fabric => "local"
    }, {
      :hostname => "vm2",
      :fabric => "local"
    }]

    localhost = `hostname -f`.chomp.downcase

    expect(@compute_controller.allocate(specs)).to eql(localhost => specs)
  end

  it 'allocates to a remote fabric' do
    allow(@compute_node_client).to receive(:audit_fabric).with("st").
      and_return("st-kvm-001.mgmt.st.net.local" => { :active_hosts => [] })

    allow(@compute_node_client).to receive(:audit_fabric).with("bs").
      and_return("bs-kvm-001.mgmt.bs.net.local" => { :active_hosts => [] })

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

    expect(allocations).to eql("st-kvm-001.mgmt.st.net.local" => [specs[0], specs[1]],
                               "bs-kvm-001.mgmt.bs.net.local" => [specs[2]])
  end

  it 'doesnt allocate the same machine twice' do
    allow(@compute_node_client).to receive(:audit_fabric).with("st").
      and_return("st-kvm-001.mgmt.st.net.local" => { :active_domains => [] },
                 "st-kvm-002.mgmt.st.net.local" => { :active_domains => ["vm0"] },
                 "st-kvm-003.mgmt.st.net.local" => { :active_domains => [] })

    specs = [
      { :hostname => "vm0", :fabric => "st" },
      { :hostname => "vm1", :fabric => "st" },
      { :hostname => "vm2", :fabric => "st" },
      { :hostname => "vm3", :fabric => "st" },
      { :hostname => "vm4", :fabric => "st" }
    ]

    allocations = @compute_controller.allocate(specs)

    expect(allocations).to eql("st-kvm-001.mgmt.st.net.local" => [specs[1], specs[4]],
                               "st-kvm-002.mgmt.st.net.local" => [specs[2]],
                               "st-kvm-003.mgmt.st.net.local" => [specs[3]])
  end

  it 'allocates by slicing specs' do
    allow(@compute_node_client).to receive(:audit_fabric).with("st").
      and_return("st-kvm-001.mgmt.st.net.local" => { :active_domains => [] },
                 "st-kvm-002.mgmt.st.net.local" => { :active_domains => [] },
                 "st-kvm-003.mgmt.st.net.local" => { :active_domains => [] })

    allow(@compute_node_client).to receive(:audit_fabric).with("bs").
      and_return("bs-kvm-001.mgmt.bs.net.local" => { :active_domains => [] },
                 "bs-kvm-002.mgmt.bs.net.local" => { :active_domains => [] })

    specs = [
      { :hostname => "vm0", :fabric => "st" },
      { :hostname => "vm1", :fabric => "st" },
      { :hostname => "vm2", :fabric => "st" },
      { :hostname => "vm3", :fabric => "st" },
      { :hostname => "vm4", :fabric => "st" },
      { :hostname => "vm5", :fabric => "bs" },
      { :hostname => "vm6", :fabric => "bs" },
      { :hostname => "vm7", :fabric => "bs" }
    ]

    allocations = @compute_controller.allocate(specs)

    expect(allocations).to eql("st-kvm-001.mgmt.st.net.local" => [specs[0], specs[3]],
                               "st-kvm-002.mgmt.st.net.local" => [specs[1], specs[4]],
                               "st-kvm-003.mgmt.st.net.local" => [specs[2]],
                               "bs-kvm-001.mgmt.bs.net.local" => [specs[5], specs[7]],
                               "bs-kvm-002.mgmt.bs.net.local" => [specs[6]])
  end

  it 'launches the vms on the allocated hosts' do
    allow(@compute_node_client).to receive(:audit_fabric).and_return("myhost" => {})

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:launch).with("myhost", specs).
      and_return([["myhost", { "vm1" => %w(success yay) }]])
    expect(@compute_node_client).to receive(:launch).with("myhost", specs)

    @compute_controller.launch(specs)
  end

  it 'machines that are already allocated should show up as that' do
    allow(@compute_node_client).to receive(:audit_fabric).and_return("myhost" => { :active_domains => ["vm2"] })

    specs = [
      {
        :hostname => "vm1",
        :fabric => "st",
        :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
      },
      {
        :hostname => "vm2",
        :fabric => "st",
        :qualified_hostnames => { :mgmt => "vm2.mgmt.st.net.local" }
      }
    ]

    allow(@compute_node_client).to receive(:launch).with("myhost", specs).
      and_return([["myhost", { "vm1" => %w(success yay) }]])
    expect(@compute_node_client).to receive(:launch).with("myhost", [specs[0]])

    already_active = []
    @compute_controller.launch(specs) do
      on :unaccounted do
        # fail "no machines should be unaccounted for"
      end
      on :already_active do |vm|
        already_active << vm
      end
    end

    expect(already_active).to eql ["vm2"]
  end

  it 'calls back when a launch is allocated' do
    allow(@compute_node_client).to receive(:audit_fabric).and_return("myhost" => {})

    specs = [{
      :hostname => "vm1",
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:launch)

    allocation = {}

    @compute_controller.launch(specs) do
      on :allocated do |vm, host|
        allocation[vm] = host
      end
    end

    expect(allocation).to eql('vm1' => 'myhost')
  end

  it 'launchraw command works' do
    specs = {
      "myhost" => [
        {
          :hostname => "vm1",
          :fabric => "st",
          :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
        },
        {
          :hostname => "vm2",
          :fabric => "st",
          :qualified_hostnames => { :mgmt => "vm2.mgmt.st.net.local" }
        }
      ]
    }

    allow(@compute_node_client).to receive(:launch).with("myhost", [specs["myhost"][0]]).
      and_return([["myhost", { "vm1" => ["success", "o noes"] }]])
    allow(@compute_node_client).to receive(:launch).with("myhost", [specs["myhost"][1]]).
      and_return([["myhost", { "vm2" => %w(success yes) }]])

    result = []

    @compute_controller.launch_raw(specs) do
      on :success do |row|
        result << row
      end
    end

    expect(result).to eql([["vm1", "o noes"], %w(vm2 yes)])
  end

  it 'calls back if any launchraw command failed' do
    specs = {
      "myhost" => [{
        :hostname => "vm1",
        :fabric => "st",
        :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
      }] }

    allow(@compute_node_client).to receive(:launch).with("myhost", specs["myhost"]).
      and_return([["myhost", { "vm1" => ["failed", "o noes"] }]])

    failure = nil

    @compute_controller.launch_raw(specs) do
      on :failure do |_vm, msg|
        failure = msg
      end
    end

    expect(failure).to eql("o noes")
  end

  it 'calls back if any launch command failed' do
    allow(@compute_node_client).to receive(:audit_fabric).and_return("myhost" => {})

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:launch).with("myhost", specs).
      and_return([["myhost", { "vm1" => ["failed", "o noes"] }]])

    failure = nil
    @compute_controller.launch(specs) do
      on :failure do |_vm, msg|
        failure = msg
      end
    end

    expect(failure).to eql("o noes")
  end

  it 'unaccounted for vms raise an error when launching' do
    allow(@compute_node_client).to receive(:audit_fabric).and_return("myhost" => {})

    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }, {
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm2.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:launch).and_return([["myhost", { "vm1" => %w(success yay) }]])

    unaccounted = []
    @compute_controller.launch(specs) do
      on :unaccounted do |vm|
        unaccounted << vm
      end
    end

    expect(unaccounted).to eql ["vm2"]
  end

  it 'will account foreach machine that is destroyed' do
    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }, {
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm2.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:clean).and_return([["host1", { "vm1" => %w(success yay) }],
                                                               ["host2", { "vm2" => %w(success hey) }]])

    successful = []
    @compute_controller.clean(specs) do
      on :success do |vm, msg|
        successful << [vm, msg]
      end
    end

    expect(successful).to eql([%w(vm1 yay), %w(vm2 hey)])
  end

  it 'unaccounted for vms (when clean is called) will be reported' do
    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }, {
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm2.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:clean).and_return([["myhost", { "vm1" => %w(success yay) }]])

    unaccounted = []
    @compute_controller.clean(specs) do
      on :unaccounted do |vm|
        unaccounted << vm
      end
    end

    expect(unaccounted).to eql(["vm2"])
  end

  it 'will call back if any nodes failed in the clean action ' do
    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }, {
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm2.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:clean).and_return([["host1", { "vm1" => ["failed", "o noes"] }],
                                                               ["host2", { "vm2" => %w(success yay) }]])

    failures = []
    @compute_controller.clean(specs) do
      on :failure do |vm, msg|
        failures << [vm, msg]
      end
    end

    expect(failures).to eql [["vm1", "o noes"]]
  end

  it 'will fail to clean up if the vm is set to be non-destroyable ' do
    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :disallow_destroy => true,
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }, {
      :hostname => "vm2",
      :fabric => "st",
      :disallow_destroy => false,
      :qualified_hostnames => { :mgmt => "vm2.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:clean).with("st", [specs[1]]).
      and_return([["st", { "vm2" => %w(success yay) }]])

    expect { @compute_controller.clean(specs) }.to raise_error 'vm1 is not destroyable'
  end

  it 'will handle responses from old-fashioned agents' do
    specs = [{
      :hostname => "vm1",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm1.mgmt.st.net.local" }
    }, {
      :hostname => "vm2",
      :fabric => "st",
      :qualified_hostnames => { :mgmt => "vm2.mgmt.st.net.local" }
    }]

    allow(@compute_node_client).to receive(:clean).and_return([["myhost", { "vm1" => "success", "vm2" => "failed" }]])

    successful = []
    failures = []
    @compute_controller.clean(specs) do
      on :success do |vm, msg|
        successful << [vm, msg]
      end
      on :failure do |vm, msg|
        failures << [vm, msg]
      end
    end

    expect(successful).to eql([%w(vm1 success)])
    expect(failures).to eql [%w(vm2 failed)]
  end
end
