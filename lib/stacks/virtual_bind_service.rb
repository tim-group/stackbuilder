module Stacks::VirtualBindService
  attr_reader :zones
  attr_accessor :forwarder_zones

  def self.extended(object)
    object.configure()
  end

  def configure()
    @ports = [53]
    add_vip_network :mgmt
    remove_vip_network :prod
    @udp = true
    @zones = [:mgmt, :prod, :front]
    @forwarder_zones = []
  end

  def remove_zone(zone)
    @zones.delete zone
  end

  def forwarder_zone(fwdr_zone)
    if fwdr_zone.kind_of?(Array)
      @forwarder_zones += fwdr_zone
    else
      @forwarder_zones << fwdr_zone
    end
    @forwarder_zones.uniq!
  end

  def zones_fqdn
    return zones.inject([]) do |zones, zone|
      if zone.eql?(:prod)
        zones << "#{@domain}"
      else
        zones << "#{zone.to_s}.#{@domain}"
      end
      zones
    end
  end

  def bind_servers_that_depend_on_me
    machine_defs = get_children_for_virtual_services(virtual_services_that_depend_on_me)
    machine_defs.reject! { |machine_def| machine_def.class != Stacks::BindServer }
    machine_defs_to_fqdns(machine_defs, [:mgmt]).sort
  end

  def bind_servers_that_i_depend_on
    machine_defs = get_children_for_virtual_services(virtual_services_that_i_depend_on)
    machine_defs.reject! { |machine_def| machine_def.class != Stacks::BindServer or !machine_def.master? }
    machine_defs_to_fqdns(machine_defs, [:mgmt]).sort
  end

  def bind_master_servers_and_zones_that_i_depend_on
    zones = nil
    machine_defs = get_children_for_virtual_services(virtual_services_that_i_depend_on)
    machine_defs.each do |machine_def|
      if machine_def.kind_of? Stacks::BindServer and machine_def.master?
        zones = {} if zones.nil?
        zones[machine_def.mgmt_fqdn] = machine_def.virtual_service.zones_fqdn
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
    all_deps.merge(bind_servers_that_i_depend_on) unless bind_servers_that_i_depend_on.nil?
    all_deps.to_a
  end

  def slave_zones_fqdn(machine_def)
    return nil if machine_def == master_server
    { master_server.mgmt_fqdn => zones_fqdn }
  end

  def instantiate_machine(name, type, index, environment)
    server_name = "#{name}-#{index}"
    server = @type.new(server_name, self, type, index, &@config_block)
    server.group = groups[i % groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    @definitions[server_name] = server
    server
  end

  def instantiate_machines(environment)
    i = 0
    index =  sprintf("%03d", i += 1)
    instantiate_machine(name, :master, index, environment)
    index =  sprintf("%03d", i += 1)
    instantiate_machine(name, :slave, index, environment)
  end

  def slave_servers
    slaves = children.inject([]) do |servers, bind_server|
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
    raise "No masters were not found! #{children}" if masters.empty?
    # Only return the first master (multi-master support not implemented)
    masters.first
  end

  def healthchecks
    healthchecks = []
    healthchecks << {
      'healthcheck' => 'MISC_CHECK',
      'arg_style'   => 'PARTICIPATION',
      'path'        => '/opt/youdevise/keepalived/healthchecks/bin/check_participation.rb',
      'url_path'    => '/participation'
    }
    zones_fqdn.each do |zone|
      if zone =~ /mgmt/
        healthchecks << {
          'healthcheck' => 'MISC_CHECK',
          'arg_style'   => 'APPEND_HOST',
          'path'        => "/usr/bin/host -4 -W 3 -t A -s apt.#{zone}"
        }
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

  def to_loadbalancer_config
    vip_nets = @vip_networks.select do |vip_network|
      not [:front].include? vip_network
    end
    lb_config = {}
    vip_nets.each do |vip_net|
      lb_config[vip_fqdn(vip_net)] = {
        'type'         => 'bind',
        'ports'        => @ports,
        'realservers'  => {
          'blue' => realserver_fqdns(vip_net)
        },
        'healthchecks' => healthchecks
      }
    end
    lb_config
  end

  private

  def realserver_fqdns(net)
    self.realservers.map { |server| server.qualified_hostname(net) }.sort
  end
end
