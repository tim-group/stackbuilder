require 'stackbuilder/stacks/namespace'

module Stacks::Services::VirtualSftpService
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def self.extended(object)
    object.configure
  end

  def configure
    @downstream_services = []
    @ports = [21, 22, 2222]
  end

  def to_loadbalancer_config(location)
    grouped_realservers = realservers(location).group_by do |_|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, grealservers|
      grealserver_fqdns = grealservers.map(&:prod_fqdn).sort
      [group, grealserver_fqdns]
    end]

    {
      vip_fqdn(:prod, location) => {
        'type'         => 'sftp',
        'ports'        => @ports,
        'realservers'  => realservers,
        'persistent_ports'  => @persistent_ports
      }
    }
  end

  def config_params(dependant, _fabric)
    fail "#{type} is not configured to provide config_params to #{dependant.type}" \
      unless dependant.type.eql?(Stacks::Services::AppServer)
    { 'sftp_servers' => fqdn_list(children, [:mgmt]) }
  end
end
