module Stacks::VirtualBindService
  attr_accessor :forwarder_zones

  def self.extended(object)
    object.configure()
  end

  def configure()
    @ports = [53]
    add_vip_network :mgmt
    @udp = true
    @zones = [:mgmt, :prod, :front]
    @forwarder_zones = []
  end

  def zones
    @zones
  end

  def forwarder_zone(fwdr_zone)
    if fwdr_zone.kind_of?(Array)
      @forwarder_zones = @forwarder_zones + fwdr_zone
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

  def bind_servers_that_depend_on_me #dependant_bind_machine_defs
    machine_defs = get_children_for_virtual_services(virtual_services_that_depend_on_me)
    machine_defs.reject! { |machine_def| machine_def.class != Stacks::BindServer }
    machine_defs_to_fqdns(machine_defs, [:mgmt]).sort
  end

  def bind_master_servers_and_zones_that_i_depend_on
    zones = nil
    machine_defs = get_children_for_virtual_services(virtual_services_that_i_depend_on)
    machine_defs.each do |child_machine_def|
      if child_machine_def.kind_of? Stacks::BindServer and child_machine_def.master?
        zones = {} if zones.nil?
        zones[child_machine_def.mgmt_fqdn] = child_machine_def.virtual_service.master_zones_fqdn
      end
    end
    zones
  end

  def master_zones_fqdn
    zones_fqdn
  end

  def all_dependencies(machine_def)
    all_deps = []
    # the directly related dependant instances (ie the master if you're a slave or the slaves if you're a master)
    all_deps += cluster_dependant_instances(machine_def)
    # indirectly related dependant instances (ie. things that say they depend on this service)
    indirect_deps = bind_servers_that_depend_on_me if machine_def.master?
    indirect_deps -= ['', nil] unless indirect_deps.nil?
    all_deps += indirect_deps unless indirect_deps.nil?
    # the reverse dependencies of the 'other dependant instances'
    virtual_services_that_i_depend_on.each do |serv|
      rev_deps = serv.children.map { |child_machine_def|
        child_machine_def.mgmt_fqdn if child_machine_def.master?
      }
      rev_deps -= ['', nil] unless rev_deps.nil?
      all_deps += rev_deps unless rev_deps.nil?
    end
    all_deps
  end

  def slave_zones_fqdn(machine_def)
    return nil if machine_def == master_server
    { master_server.mgmt_fqdn => master_server.zones_fqdn }
  end

  def instantiate_machine(name, type, index, environment)
    server_name = "#{name}-#{index}"
    server = @type.new(server_name, self, type, index, &@config_block)
    server.group = groups[i%groups.size] if server.respond_to?(:group)
    server.availability_group = availability_group(environment) if server.respond_to?(:availability_group)
    @definitions[server_name] = server
    server
  end

  def realserver_prod_fqdns
    self.realservers.map { |server| server.prod_fqdn }.sort
  end

  def realserver_mgmt_fqdns
    self.realservers.map { |server| server.mgmt_fqdn }.sort
  end

  def instantiate_machines(environment)
    i = 0
    index =  sprintf("%03d",i+=1)
    instantiate_machine(name, :master, index, environment)
    index =  sprintf("%03d",i+=1)
    instantiate_machine(name, :slave, index, environment)
  end

  def slave_servers
    slaves = children.inject([]) do |servers, bind_server|
      servers << bind_server.mgmt_fqdn unless bind_server.master?
      servers
    end
  end

  def cluster_dependant_instances(machine_def)
    instances = []
    instances+=slave_servers if machine_def.master? # for xfer
    instances << master_server.mgmt_fqdn if machine_def.slave? # for notify
    instances
  end

  def master_server
    masters = children.reject { |bind_server| !bind_server.master? }
    raise "No masters were not found! #{children}" if masters.empty?
    #Only return the first master (multi-master support not implemented)
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
    prod_realservers = {'blue' => realserver_prod_fqdns}
    mgmt_realservers = {'blue' => realserver_mgmt_fqdns}
    {
      self.vip_fqdn(:prod) => {
        'type'         => 'bind',
        'ports'        => @ports,
        'realservers'  => prod_realservers,
        'healthchecks' => healthchecks
      },
      self.vip_fqdn(:mgmt) => {
        'type'         => 'bind',
        'ports'        => @ports,
        'realservers'  => mgmt_realservers,
        'healthchecks' => healthchecks
      }
    }
  end
end
