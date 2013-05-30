
describe 'launch' do
  class HostRepository
    attr_accessor :machine_repo

    def find_current
      result = audit()
      result.each.each do |vm|
        machine_repo.find(vm)
      end
      host = Host.new(:allocated_machines=>nil, :policies=>nil, :preferences=>nil)
    end
  end


  class Host
    attr_accessor :allocated_machines
    attr_accessor :provisionally_allocated_machines
    attr_accessor :fqdn

    def initialize(fqdn)
      @provisionally_allocated_machines = []
      @fqdn = fqdn
      @allocated_machines = []
    end

    def machines
      # merge allocated and provisionally_allocated
      @provisionally_allocated_machines
    end

    def provisionally_allocate(machine)
      @provisionally_allocated_machines << machine
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

    def initialize(args)
      @hosts = args[:hosts]
      @next_increment = 0
    end

    private
    def find_suitable_host_for(machine)
      #    candidate_hosts = hosts.reject do |host|
      #      !host.can_allocate(host)
      #    end.order_by utility
      #    candidate_hosts[0]

      candidate_host = hosts[@next_increment % hosts.size]
      @next_increment=@next_increment+1
      return candidate_host
    end

    def unallocated_machines(machines)
      allocated_machines = []
      hosts.each do |host|
        host.allocated_machines.each do |machine|
          allocated_machines << machine
        end
      end

      return machines - allocated_machines
    end

    public
    def allocate(machines)
      unallocated_machines = unallocated_machines(machines)

      unallocated_machines.each do |machine|
        host = find_suitable_host_for(machine)
        host.provisionally_allocate(machine)
      end
    end

    def to_unlaunched_specs
      Hash[@hosts.map do |host|
        specs = host.provisionally_allocated_machines.map do |machine|
          machine.to_spec
        end
        [host.fqdn, specs]
      end].reject {|host, specs| specs.size==0}
    end
  end

  class Services
    attr_accessor :host_repo
    attr_accessor :compute_controller

    def initialize(arguments)
      @host_repo = arguments[:host_repo]
      @compute_controller = arguments[:compute_controller]
    end
  end

  require 'stacks/namespace'

  module Stacks::Actions
    attr_accessor :actions
    def self.extended(object)
      object.actions = {}

      object.action 'launch' do |services, machine_def|
        hosts = services.host_repo.find_current()
        hosts.allocate(machine_def.flatten)
        specs = hosts.to_unlaunched_specs()
        services.compute_controller.launch(specs)
      end

    end

    def self.included(object)
      self.extended(object)
    end

    def action(name, &block)
      @actions = {name=> block}
    end

    def get_action(name)
      @actions[name]
    end
  end

  before do
    extend Stacks::DSL
    extend Stacks::Actions
  end

  def test_env_with_refstack
    stack "ref" do
      virtual_appserver "refapp"
    end

    env "test", :primary_site => "t" do
      instantiate_stack "ref"
    end

    find_environment("test")
  end

  def host_repo_with_hosts(n, &block)
    host_repo = double
    hosts = []
    n.times do |i|
      host = Host.new("h#{i+1}")
      block.call(host) unless block.nil?
      hosts << host
    end

    host_repo.stub(:find_current).and_return(Hosts.new(:hosts=>hosts))
    host_repo
  end


  it 'will allocate and launch a bunch of machines' do
    env = test_env_with_refstack
    compute_controller = double
    services = Services.new(
      :host_repo => host_repo_with_hosts(2),
      :compute_controller=> compute_controller)

      compute_controller.should_receive(:launch).with(
        "h1" => [find("test-refapp-001.mgmt.t.net.local").to_spec],
        "h2" => [find("test-refapp-002.mgmt.t.net.local").to_spec]
      )

      get_action("launch").call(services, env)
  end

  it 'will not allocate machines that are already allocated' do
    env = test_env_with_refstack
    compute_controller = double
    host_repo = host_repo_with_hosts(2) do |host|
      host.allocated_machines << find("test-refapp-001.mgmt.t.net.local")
    end
    services = Services.new(
      :host_repo => host_repo,
      :compute_controller=> compute_controller)

      compute_controller.should_receive(:launch).with(
        "h1" => [find("test-refapp-002.mgmt.t.net.local").to_spec]
      )

      get_action("launch").call(services, env)
  end

end
