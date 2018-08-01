require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveHpilo
  include Support::MCollective

  def update_ilo_firmware(host_fqdn)
    do_hpilo_call(host_fqdn, "update_rib_firmware", :version => "latest")
  end

  def set_one_time_network_boot(host_fqdn)
    do_hpilo_call(host_fqdn, "set_one_time_boot", :device => "network")
  end

  def power_off_host(host_fqdn)
    do_hpilo_call(host_fqdn, "power_off")
    sleep 2 while get_host_power_status(host_fqdn) == 'ON'
  end

  def power_on_host(host_fqdn)
    do_hpilo_call(host_fqdn, "power_on")
    sleep 2 while get_host_power_status(host_fqdn) == 'OFF'
  end

  def get_host_power_status(host_fqdn)
    result = do_hpilo_call(host_fqdn, "power_status")
    result[:power]
  end

  def get_mac_address(host_fqdn)
    result = do_hpilo_call(host_fqdn, "get_host_data")
    result[:output][:mac_address]
  end

  private

  def ilo_site_for(site)
    site == 'oy' ? 'oy' : 'pg'
  end

  def ilo_details(host_fqdn)
    host, _, full_domain = host_fqdn.partition('.')
    _, _, site_domain = full_domain.partition('.')
    site, _, company_domain = site_domain.partition('.')

    ilo_site = ilo_site_for(site)

    ["#{host}.ilo.#{ilo_site}.#{company_domain}", ilo_site]
  end

  def do_hpilo_call(host_fqdn, action, args_hash = {}, attempts = 3)
    ilo_host_fqdn, ilo_fabric = ilo_details(host_fqdn)
    args_hash[:host_fqdn] = ilo_host_fqdn

    rsps = mco_client("hpilo", :timeout => 300, :fabric => ilo_fabric) { |mco| mco.send(action, args_hash) }

    unless rsps.size == 1 && rsps[0][:statuscode] == 0
      if attempts > 1
        logger(Logger::WARN) { "hpilo #{action} operation failed with #{status_of(rsps[0])}, retrying..." }
        return do_hpilo_call(host_fqdn, action, args_hash, attempts - 1)
      end
      logger(Logger::FATAL) { "hpilo #{action} operation failed with #{status_of(rsps[0])}" }
      fail "no response to mco hpilo call to #{ilo_host_fqdn}" unless rsps.size == 1
      fail "failed during mco hpilo call to #{ilo_host_fqdn}: #{rsps[0][:statusmsg]}" unless rsps[0][:statuscode] == 0
    end

    logger(Logger::DEBUG) { "Successfully carried out mco hpilo #{action} operation on #{rsps[0][:sender]}" }
    rsps[0][:data]
  end

  def status_of(resp)
    resp.nil? ? 'no response' : resp[:statusmsg]
  end
end
