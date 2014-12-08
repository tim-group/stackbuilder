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

  def to_spec
    spec = super
    spec[:template] = "sehub"
    spec[:nodes] = @nodes.map {|name,node| node.name}.reject{|name,node| name==self.name}.sort
    spec[:selenium_version] = options[:selenium_version] || "2.32.0"
    spec
  end
end
