require 'stackbuilder/stacks/services/selenium/namespace'

class Stacks::Services::Selenium::UbuntuNode < Stacks::MachineDef
  attr_reader :hub
  attr_reader :options

  def initialize(base_hostname, hub, options)
    @base_hostname = base_hostname
    @networks = [:mgmt]
    @hub = hub
    @options = options
    @routes = []
    @location = :primary_site
    @added_cnames = []
    @destroyable = true
    @ram = "2097152"
    @allocation_tags = []
    @storage = {
      '/'.to_sym =>  {
        :type        => 'os',
        :size        => '5G',
        :prepare     => {
          :method => 'image',
          :options => {}
        }
      }
    }
    template(options[:lsbdistcodename].nil? ? :precise : options[:lsbdistcodename])
  end

  def to_enc
    super
    {}
  end

  def validate_storage
    true
  end

  def to_spec
    spec = super
    spec[:template] = "senode_#{options[:lsbdistcodename]}"
    spec[:selenium_hub_host] = hub.mgmt_fqdn unless hub.nil?
    spec[:selenium_deb_version] = options[:selenium_deb_version] || "2.32.0"
    spec[:selenium_node_deb_version] = options[:selenium_node_deb_version] || "3.0.7"
    spec[:firefox_version] = options[:firefox_version]
    spec[:chrome_version] = options[:chrome_version]

    spec
  end
end
