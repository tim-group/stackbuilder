require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveHpilo
  include Support::MCollective

  def update_ilo_firmware(host_fqdn, fabric)
    do_hpilo_call(fabric, "update_rib_firmware", :host_fqdn => to_ilo_host_fqdn(host_fqdn), :version => "latest")
  end

  def set_one_time_network_boot(host_fqdn, fabric)
    do_hpilo_call(fabric, "set_one_time_boot", :host_fqdn => to_ilo_host_fqdn(host_fqdn), :device => "network")
  end

  def power_off_host(host_fqdn, fabric)
    do_hpilo_call(fabric, "power_off", :host_fqdn => to_ilo_host_fqdn(host_fqdn))
    sleep 2 while get_host_power_status(host_fqdn, fabric) == 'ON'
  end

  def power_on_host(host_fqdn, fabric)
    do_hpilo_call(fabric, "power_on", :host_fqdn => to_ilo_host_fqdn(host_fqdn))
    sleep 2 while get_host_power_status(host_fqdn, fabric) == 'OFF'
  end

  def get_host_power_status(host_fqdn, fabric)
    result = do_hpilo_call(fabric, "power_status", :host_fqdn => to_ilo_host_fqdn(host_fqdn))
    result[:power]
  end

  def get_mac_address(host_fqdn, fabric)
    result = do_hpilo_call(fabric, "get_host_data", :host_fqdn => to_ilo_host_fqdn(host_fqdn))
    result[:output][:mac_address]
  end

  private

  def to_ilo_host_fqdn(host_fqdn)
    host_fqdn.sub("mgmt", "ilo")
  end

  def do_hpilo_call(fabric, action, args_hash, attempts = 3)
    rsps = mco_client("hpilo", :timeout => 300, :fabric => fabric) { |mco| mco.send(action, args_hash) }

    unless rsps.size == 1 && rsps[0][:statuscode] == 0
      if attempts > 1
        logger(Logger::WARN) { "hpilo #{action} operation failed with #{status_of(rsps[0])}, retrying..." }
        return do_hpilo_call(fabric, action, args_hash, attempts - 1)
      end
      logger(Logger::FATAL) { "hpilo #{action} operation failed with #{status_of(rsps[0])}" }
      fail "no response to mco hpilo call for fabric #{fabric}" unless rsps.size == 1
      fail "failed during mco hpilo call for fabric #{fabric}: #{rsps[0][:statusmsg]}" unless rsps[0][:statuscode] == 0
    end

    logger(Logger::DEBUG) { "Successfully carried out mco hpilo #{action} operation on #{rsps[0][:sender]}" }
    rsps[0][:data]
  end

  def status_of(resp)
    resp.nil? ? 'no response' : resp[:statusmsg]
  end
end
