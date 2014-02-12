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

  def find_virtual_service(service)
    environment.accept do |machine_def|
      if machine_def.kind_of? Stacks::VirtualService and service.eql? machine_def.name
        return machine_def
      end
    end

    raise "Cannot find the service called #{service}"
  end


  private
  def resolve_virtual_services(dependencies)
    dependencies.map do |dependency|
      find_virtual_service(dependency)
    end
  end

  public
  def to_enc()

    deps = Hash[resolve_virtual_services(virtual_service.depends_on).map do |dependency|
      [dependency.application + ".url", "http://" + dependency.vip_fqdn + ":8000"]
    end]

    enc = {
      'role::http_app' => {
      'application' => virtual_service.application,
      'group' => group,
      'environment' => environment.name,
      'dependencies' => deps
    }}

    if @virtual_service.respond_to? :vip_fqdn
      enc['role::http_app']['vip_fqdn'] = @virtual_service.vip_fqdn
    end
    enc
  end
end
