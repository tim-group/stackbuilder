module Stacks::VirtualBindService
  def self.extended(object)
    object.configure()
  end

  def configure()
    @ports = [53]
    add_vip_network :mgmt
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
    [masters.first.prod_fqdn]
  end

  def to_loadbalancer_config
    prod_realservers = {'blue' => realserver_prod_fqdns}
    mgmt_realservers = {'blue' => realserver_mgmt_fqdns}

    {
      self.vip_fqdn(:prod) => {
        'type' => 'dns',
        'ports' => @ports,
        'realservers' => prod_realservers
      },
      self.vip_fqdn(:mgmt) => {
        'type' => 'dns',
        'ports' => @ports,
        'realservers' => mgmt_realservers
      }
    }
  end
end
