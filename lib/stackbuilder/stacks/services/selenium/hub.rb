require 'stackbuilder/stacks/services/selenium/namespace'

class Stacks::Services::Selenium::Hub < Stacks::MachineDef
  attr_reader :options

  def initialize(base_hostname, nodes, options)
    @base_hostname = base_hostname
    @networks = [:mgmt]
    @nodes = nodes
    @options = options
    @routes = []
    @location = :primary_site
    @added_cnames = []
    @ram = "2097152"
    @destroyable = true
    @allocation_tags = []
    @storage = {
      '/'.to_sym =>  {
        :type        => 'os',
        :size        => '5G',
        :prepare     => {
          :method => 'image',
          :options => {
            :path => '/var/local/images/gold-precise/generic.img'
          }
        }
      }
    }
  end

  def bind_to(environment)
    super(environment)
  end

  def validate_storage
    true
  end

  def node_names
    node_names = @nodes.inject([]) do |hostnames, (_name, machine)|
      hostnames << machine.hostname if machine.is_a? Stacks::MachineDef
      machine.children.map do|child_machine|
        hostnames << child_machine.hostname
      end if machine.is_a? Stacks::MachineSet
      hostnames
    end
    node_names.reject! { |name| name == self.name }.sort
  end

  def to_spec
    spec = super
    spec[:template] = "sehub"
    spec[:nodes] = node_names
    spec[:selenium_deb_version] = options[:selenium_deb_version] || "2.32.0"
    spec
  end
end
