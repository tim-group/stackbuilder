module Stacks::Services::VirtualBindService
  attr_reader :zones
  attr_accessor :forwarder_zones
  attr_accessor :slave_instances

  def self.extended(object)
    object.configure
  end

  def configure
    @ports = [53]
    add_vip_network :mgmt
    remove_vip_network :prod
    @udp = true
    @zones = [:mgmt, :prod, :front]
    @forwarder_zones = []
    @slave_instances = 1
  end

  def add_zone(zone)
    @zones << zone unless @zones.include? zone
  end

  def remove_zone(zone)
    @zones.delete zone
  end

  def forwarder_zone(fwdr_zone)
    if fwdr_zone.is_a?(Array)
      @forwarder_zones += fwdr_zone
    else
      @forwarder_zones << fwdr_zone
    end
    @forwarder_zones.uniq!
  end

  def zones_fqdn(location)
    fabric = environment.options[location]
    fqdn_zones = []
    zones.map do |zone|
      fqdn_zones << environment.domain(fabric, zone.to_sym)
    end
    fqdn_zones
  end

  def bind_servers_that_depend_on_me
    machine_defs = get_children_for_virtual_services(virtual_services_that_depend_on_me)
    machine_defs.reject! { |machine_def| machine_def.class != Stacks::Services::BindServer }
    machine_defs.map(&:mgmt_fqdn).sort
  end

  def bind_servers_that_i_depend_on
    machine_defs = get_children_for_virtual_services(virtual_services_that_i_depend_on)
    machine_defs.reject! { |machine_def| machine_def.class != Stacks::Services::BindServer || !machine_def.master? }
    machine_defs.map(&:mgmt_fqdn).sort
  end

  def bind_master_servers_and_zones_that_i_depend_on(location)
    zones = nil
    machine_defs = get_children_for_virtual_services(virtual_services_that_i_depend_on)
    machine_defs.each do |machine_def|
      if machine_def.is_a?(Stacks::Services::BindServer) && machine_def.master?
        zones = {} if zones.nil?
        zones[machine_def.mgmt_fqdn] = machine_def.virtual_service.zones_fqdn(location)
      end
    end
    zones
  end

  def all_dependencies(machine_def)
    all_deps = Set.new
    # the directly related dependant instances (ie the master if you're a slave or the slaves if you're a master)
    all_deps.merge(cluster_dependant_instances(machine_def))
    # indirectly related dependant instances (ie. things that say they depend on this service)
    indirect_deps = bind_servers_that_depend_on_me if machine_def.master?
    all_deps.merge(indirect_deps) unless indirect_deps.nil?
    all_deps.merge(bind_servers_that_i_depend_on)
    all_deps.to_a.sort
  end

  def slave_zones_fqdn(bind_server)
    return nil if bind_server == master_server
    { master_server.mgmt_fqdn => zones_fqdn(bind_server.location) }
  end

  def instantiate_machine(type, i, environment, networks, location)
    index = sprintf("%03d", i + 1)
    server = @type.new(type, self, index, networks, location)
    server.group = groups[i % groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    @definitions[random_name] = server
    server
  end

  def instantiate_machines(environment)
    fail 'Bind servers do not currently support enable_secondary_site' if @enable_secondary_site

    i = 0
    instantiate_machine(:master, i, environment, default_networks, :primary_site)
    @slave_instances.times do
      instantiate_machine(:slave, i += 1, environment, default_networks, :primary_site)
    end
  end

  def slave_servers
    children.inject([]) do |servers, bind_server|
      servers << bind_server unless bind_server.master?
      servers
    end
  end

  def slave_servers_as_fqdns
    slave_servers.map(&:mgmt_fqdn)
  end

  def cluster_dependant_instances(machine_def)
    instances = []
    instances += slave_servers_as_fqdns if machine_def.master? # for xfer
    instances << master_server.mgmt_fqdn if machine_def.slave? # for notify
    instances
  end

  def master_server
    masters = children.reject { |bind_server| !bind_server.master? }
    fail "No masters were not found! #{children}" if masters.empty?
    # Only return the first master (multi-master support not implemented)
    masters.first
  end

  def healthchecks(location)
    healthchecks = []
    healthchecks << {
      'healthcheck' => 'MISC_CHECK',
      'arg_style'   => 'PARTICIPATION',
      'path'        => '/opt/youdevise/keepalived/healthchecks/bin/check_participation.rb',
      'url_path'    => '/participation'
    }
    zones_fqdn(location).each do |zone|
      case zone
      when /mgmt/
        healthchecks << {
          'healthcheck' => 'MISC_CHECK',
          'arg_style'   => 'APPEND_HOST',
          'path'        => "/usr/bin/host -4 -W 3 -t A -s apt.#{zone}"
        }
      when /crosssite/, /glue/
        # do nothing
      else
        healthchecks << {
          'healthcheck' => 'MISC_CHECK',
          'arg_style'   => 'APPEND_HOST',
          'path'        => "/usr/bin/host -4 -W 3 -t A -s gw-vip.#{zone}"
        }
      end
    end
    healthchecks
  end

  def to_loadbalancer_config(location, fabric)
    vip_nets = @vip_networks.select do |vip_network|
      ![:front].include? vip_network
    end
    lb_config = {}
    vip_nets.each do |vip_net|
      lb_config[vip_fqdn(vip_net, fabric)] = {
        'type'         => 'bind',
        'ports'        => @ports,
        'realservers'  => {
          'blue' => realservers(location).map { |server| server.qualified_hostname(vip_net) }.sort
        },
        'healthchecks' => healthchecks(location)
      }
    end
    lb_config
  end
end
