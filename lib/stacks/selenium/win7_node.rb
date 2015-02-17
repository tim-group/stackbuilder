require 'stacks/selenium/namespace'

class Stacks::Selenium::Win7Node < Stacks::MachineDef
  attr_reader :hub
  attr_reader :options

  def initialize(base_hostname, hub, options)
    super(base_hostname, [:mgmt])
    @hub = hub
    @options = options
    modify_storage({ '/'.to_sym => { :size => '15G' } })
  end

  def bind_to(environment)
    super(environment)
  end

  def to_spec
    spec = super
    spec[:template] = "win7boot"
    spec[:gold_image_url] = options[:gold_image] # TODO: delete me

    if not self.hub.nil?
      spec[:selenium_hub_host] = self.hub.mgmt_fqdn
    end
    spec[:selenium_version] = options[:selenium_version] || "2.32.0" # TODO: Remove default once refstack has been updated to pass in :ie_version
    spec[:ie_version] = options[:ie_version]
    spec[:storage]['/'.to_sym][:prepare] = {} if spec[:storage]['/'.to_sym][:prepare].nil?
    spec[:storage]['/'.to_sym][:prepare][:options] = {} if spec[:storage]['/'.to_sym][:prepare][:options].nil?
    spec[:storage]['/'.to_sym][:prepare][:options][:resize] = false
    spec[:storage]['/'.to_sym][:prepare][:options][:path] = options[:gold_image]
    spec[:storage]['/'.to_sym][:prepare][:options][:create_in_fstab] = false

    spec
  end
end
