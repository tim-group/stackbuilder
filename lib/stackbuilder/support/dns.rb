require 'stackbuilder/support/namespace'

class Support::Dns
  def initialize(factory, core_actions)
    @factory = factory
    @core_actions = core_actions
  end

  def do_allocate_ips(machine_def)
    @core_actions.get_action("allocate_ips").call(@factory.services, machine_def)
  end

  def do_free_ips(machine_def)
    @core_actions.get_action("free_ips").call(@factory.services, machine_def)
  end

  def do_allocate_vips(machine_def)
    vips = find_vips(machine_def)
    if vips.empty?
      logger(Logger::INFO) { 'no vips to allocate' }
    else
      @factory.services.dns.allocate(vips)
    end
  end

  def do_free_vips(machine_def)
    @factory.services.dns.free(find_vips(machine_def))
  end

  private

  def find_vips(machine_def)
    vips = []
    machine_def.accept do |child_machine_def|
      if child_machine_def.respond_to?(:to_vip_spec)
        vips << child_machine_def.to_vip_spec(:primary_site)
        if child_machine_def.enable_secondary_site || child_machine_def.sites.include?(child_machine_def.environment.secondary_site)
          vips << child_machine_def.to_vip_spec(:secondary_site)
        end
      end
    end
    vips
  end
end
