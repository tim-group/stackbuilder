require 'stacks/selenium/namespace'

class Stacks::Selenium::Hub < Stacks::MachineDef
  attr_reader :options

  def initialize(base_hostname, nodes, options)
    super(base_hostname, [:mgmt])
    @nodes = nodes
    @options = options
  end

  def bind_to(environment)
    super(environment)
  end

  def node_names
    node_names = @nodes.inject([]) do |hostnames, (name, machine)|
      hostnames << machine.hostname if machine.kind_of? Stacks::MachineDef
      machine.children.map {|child_machine|
        hostnames << child_machine.hostname
      } if machine.kind_of? Stacks::MachineSet
      hostnames
    end
    node_names.reject! { |name| name == self.name }.sort
  end

  def to_spec
    spec = super
    spec[:template] = "sehub"
    spec[:nodes] = node_names
    spec[:selenium_version] = options[:selenium_version] || "2.32.0"
    spec
  end
end
