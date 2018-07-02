require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveNrpe
  include Support::MCollective

  def run_all_commands(fqdn, attempts = 3)
    rsps = mco_client("nrpe", :timeout => 30, :nodes => [fqdn]) { |mco| mco.runallcommands }
    failed = (rsps.size != 1 || rsps[0][:statuscode] != 0 || rsps[0][:data][:commands].nil?)

    if failed
      return run_all_commands(fqdn, attempts - 1) if attempts > 1

      if rsps.size == 0
        fail "Got no response from mcollective nrpe.runallcommands request to #{fqdn}"
      else
        fail "failed to perform nrpe checks on #{fqdn}: #{rsps[0][:statusmsg]}" unless rsps[0][:statuscode] == 0
      end
    end

    result = rsps[0][:data][:commands]
    fail "No nrpe checks executed on #{fqdn}" if result.nil? || result.empty?

    result
  end
end
