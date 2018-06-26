require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveNagsrv
  include Support::MCollective

  def schedule_downtime(machine, duration)
    fqdn = machine.mgmt_fqdn
    logger(Logger::INFO) { "Scheduling downtime for #{fqdn}" }
    mco_client("nagsrv", :fabric => machine.fabric) do |mco|
      mco.class_filter('nagios')
      mco.schedule_host_downtime(:host => fqdn, :duration => duration).map do |response|
        "#{response[:sender]} = #{response[:statuscode] == 0 ? 'OK' : 'Failed'}: #{response[:statusmsg]}"
      end
    end.join(',')
  end

  def cancel_downtime(machine)
    fqdn = machine.mgmt_fqdn
    logger(Logger::INFO) { "Cancelling downtime for #{fqdn}" }
    mco_client("nagsrv", :fabric => machine.fabric) do |mco|
      mco.class_filter('nagios')
      mco.del_host_downtime(:host => fqdn).map do |response|
        "#{response[:sender]} = #{response[:statuscode] == 0 ? 'OK' : 'Failed'}: #{response[:statusmsg]}"
      end.join(',')
    end
  end
end
