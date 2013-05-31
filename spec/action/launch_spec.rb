### TODO
###   pull out round robinning thing
##    define correct way to add policies and preference algo
##
describe 'launch' do
  class HostRepository
    attr_accessor :machine_repo

    def find_current
      result = audit()
      result.each.each do |vm|
        machine_repo.find(vm)
      end
      host = Host.new(:allocated_machines=>nil, :policies=>nil)
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
      @policies = []
      @preference_functions = []
    end

    def machines
      provisionally_allocated_machines + allocated_machines
    end

    def provisionally_allocate(machine)
      @provisionally_allocated_machines << machine
    end

    def add_policy(&block)
      @policies << block
    end

    def set_preference_functions(functions)
      @preference_functions = functions
    end

    def add_preference_function(&block)
      @preference_functions << block
    end

    def has_preference_function?
      return  @preference_functions.size>0
    end

    def can_allocate(machine)
      @policies.each do |policy|
        return false unless policy.call(self, machine)
      end
      return true
    end

    def preference(machine)
      @preference_functions.map do |function|
        function.call(self)
      end
    end
  end

  module HostPreference

    def self.least_machines()
      Proc.new do |host|
        host.machines.size
      end
    end

    def self.alphabetical_fqdn()
      Proc.new do |host|
        host.fqdn
      end
    end

  end

  class Hosts
    attr_accessor :hosts

    def initialize(args)
      @hosts = args[:hosts]
      hosts.each do |host|
        host.set_preference_functions(args[:preference_functions])
      end
    end

    private
    def find_suitable_host_for(machine)
      candidate_hosts = hosts.reject do |host|
          !host.can_allocate(machine)
      end.sort_by do |host|
        host.preference(machine)
      end

      candidate_host = candidate_hosts[0]
      next_host = candidate_hosts[candidate_hosts.index(candidate_host)+1]
      @next_increment=hosts.index(next_host)
      candidate_host
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

    def standard_preference_functions
      return [HostPreference.least_machines(), HostPreference.alphabetical_fqdn]
    end


  def host_repo_with_hosts(n, preference_functions=standard_preference_functions, &block)
    host_repo = double
    hosts = []
    n.times do |i|
      host = Host.new("h#{i+1}")
      block.call(host,i) unless block.nil?
      hosts << host
    end

    host_repo.stub(:find_current).and_return(Hosts.new(:hosts=>hosts, :preference_functions=>preference_functions))
    host_repo
  end

  it 'will allocate and launch a bunch of machines' do
    env = test_env_with_refstack
    compute_controller = double
    services = Services.new(
      :host_repo => host_repo_with_hosts(3),
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
    host_repo = host_repo_with_hosts(2) do |host,i|
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

  it 'will not allocate to the machine with the highest preference' do
    env = test_env_with_refstack
    compute_controller = double

    chooseh3 = Proc.new do |host|
        if host.fqdn =~/h3/
          0
        else
          1
        end
    end

    host_repo = host_repo_with_hosts(3, [chooseh3])

    services = Services.new(
      :host_repo => host_repo,
      :compute_controller=> compute_controller)

      compute_controller.should_receive(:launch).with(
        "h3" => [find("test-refapp-001.mgmt.t.net.local").to_spec,
          find("test-refapp-002.mgmt.t.net.local").to_spec]
      )

      get_action("launch").call(services, env)
  end

  it 'will not allocate to a machine that fails a policy' do
    env = test_env_with_refstack
    compute_controller = double
    host_repo = host_repo_with_hosts(3) do |host, i|
      host.add_policy do |host, machine|
        host.fqdn !~ /h2/
      end
    end

    services = Services.new(
      :host_repo => host_repo,
      :compute_controller=> compute_controller)

      compute_controller.should_receive(:launch).with(
        "h1" => [find("test-refapp-001.mgmt.t.net.local").to_spec],
        "h3" => [find("test-refapp-002.mgmt.t.net.local").to_spec]
      )

      get_action("launch").call(services, env)
  end


  ha_policy = Proc.new do |host, machine|
    host.machines.each do |m|
      if m.group == machine.group
        NO
      end
    end
  end

  enough_ram_policy = Proc.new do |host, machine|
    host.ram - machine.ram >0
  end

end
