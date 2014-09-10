require 'stacks/namespace'
require 'stacks/machine_def'

class Stacks::AppServer < Stacks::MachineDef

  attr_reader :environment, :virtual_service
  attr_accessor :group

  def initialize(virtual_service, index, &block)
    super(virtual_service.name + "-" + index)
    @virtual_service = virtual_service
  end

  def bind_to(environment)
    super(environment)
  end

  def vip_fqdn
    return @virtual_service.vip_fqdn
  end

  public
  def to_enc()
    enc = {
      'role::http_app' => {
        'application' => virtual_service.application,
        'group' => group,
        'environment' => environment.name,
        'dependencies' => @virtual_service.dependency_config,
        'dependant_instances' => @virtual_service.dependant_instances,
        'port' => '8000'
      }
    }

    if @virtual_service.respond_to? :vip_fqdn
      enc['role::http_app']['vip_fqdn'] = @virtual_service.vip_fqdn
    end

    if @virtual_service.ehcache
      peers = @virtual_service.children.map do |child|
        child.qualified_hostname(:prod)
      end

      peers.delete self.qualified_hostname(:prod)

      unless peers == []
        enc['role::http_app']['dependencies']['cache.peers'] = "[\"#{peers.join(',')}\"]"
      end
    end
    enc
  end
end
