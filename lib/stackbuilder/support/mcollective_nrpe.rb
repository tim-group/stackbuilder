require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveNrpe
  include Support::MCollective

  def run_all_commands(host_fqdn)
    mco_results = mco_client("nrpe", :nodes => [host_fqdn]) do |mco|
      mco.runallcommands.map do |result|
        fail "failed to perform nrpe checks on #{host_fqdn}: #{result[:statusmsg]}" if result[:statuscode] != 0
        result[:data][:commands]
      end
    end
    fail "Got no response from mcollective nrpe.runallcommands request to #{host_fqdn}" if mco_results.empty?

    check_results = mco_results[0]
    fail "No nrpe checks executed on #{host_fqdn}" if check_results.nil? || check_results.empty?
    check_results
  end
end
