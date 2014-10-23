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
      servers << bind_server.prod_fqdn unless bind_server.master?
      servers
    end
  end

  def master_server
    masters = children.reject { |bind_server| !bind_server.master? }
    raise "No masters were not found! #{children}" if masters.empty?
    #Only return the first master (multi-master support not implemented)
    masters.first.prod_fqdn
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
