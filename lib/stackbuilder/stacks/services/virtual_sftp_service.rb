require 'stackbuilder/stacks/namespace'

module Stacks::Services::VirtualSftpService
  attr_reader :proxy_vhosts
  attr_reader :proxy_vhosts_lookup

  def self.extended(object)
    object.configure
  end

  def configure
    @downstream_services = []
    @ports = {
      'proftpd' => {
        'port' => 21
      },
      'ssh' => {
        'port' => 22
      },
      'proftpd-ssh' => {
        'port' => 2222
      }
    }
  end

  def to_loadbalancer_config(location, fabric)
    servers = realservers(location).size
    monitor_warn = vip_warning_members.nil? ? calc_vip_warning_members(servers) : vip_warning_members

    grouped_realservers = realservers(location).group_by do |_|
      'blue'
    end

    realservers = Hash[grouped_realservers.map do |group, grealservers|
      grealserver_fqdns = grealservers.map(&:prod_fqdn).sort
      [group, grealserver_fqdns]
    end]

    {
      vip_fqdn(:prod, fabric) => {
        'type'              => 'sftp',
        'ports'             => @ports.keys.map { |port_name| @ports[port_name]['port'] },
        'realservers'       => realservers,
        'persistent_ports'  => @persistent_ports,
        'monitor_warn'      => monitor_warn.to_s
      }
    }
  end

  def config_params(dependant, _fabric, _dependent_instance)
    fail "#{type} is not configured to provide config_params to #{dependant.type}" \
      unless dependant.type.eql?(Stacks::Services::AppServer)
    { 'sftp_servers' =>  children.map(&:mgmt_fqdn).sort }
  end
end
