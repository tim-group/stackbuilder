module Stacks::VirtualNameService
  def self.extended(object)
    object.configure()
  end

  def configure()
    @ports = [53]
    add_vip_network :mgmt
  end

  def realserver_prod_fqdns
    self.realservers.map { |server| server.prod_fqdn }.sort
  end

  def realserver_mgmt_fqdns
    self.realservers.map { |server| server.mgmt_fqdn }.sort
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
