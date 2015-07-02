
describe 'launch' do
  class HostRepository
    attr_accessor :machine_repo

    def find_compute_nodes
      result = audit
      result.each.each do |vm|
        machine_repo.find(vm)
      end
      Host.new(:allocated_machines => nil, :policies => nil, :preferences => nil)
    end
  end

  class Host
    attr_accessor :allocated_machines
    attr_accessor :provisionally_allocated_machines

    def machines
      # merge allocated and provisionally_allocated
    end

    def provisionally_allocate(_machine)
    end

    def can_allocate(machine)
      policies.check(machine)
      # exclude if asking for too much disk
      # exclude if asking for too much ram
      # exclude if already contains a machine in this host group
    end

    def utility(machine)
      preferences.rate(machine)
    end
  end

  class Hosts
    attr_accessor :hosts

    private

    def find_suitable_host_for(_machine)
      candidate_hosts = hosts.reject do |host|
        !host.can_allocate(host)
      end.order_by utility
      candidate_hosts[0]
    end

    def allocate(machines, hosts)
      unallocated_machines = hosts.remove_from_list_if_allocated(machines)

      unallocated_machines.each do |machine|
        host = find_suitable_host_for(machine)
        host.provisionally_allocate(machine)
      end
    end
  end

  action 'launch' do |services, machine_def|
    hosts = services.host_repo.find_compute_nodes
    hosts.allocate(machine_def.flatten)
    services.compute_controller.launch(nil)
  end

  it 'will allocate and launch a bunch of machines' do
    stack "ref" do
      virtual_app_service "refapp"
    end

    actions.services.host_repo = double
    actions.services.compute_controller = double

    run_action "launch", machine_def
  end
end
