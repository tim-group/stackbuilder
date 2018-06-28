require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveRpcutil
  include Support::MCollective

  def ping(fqdn, attempts = 3)
    rsps = mco_client("rpcutil", :timeout => 30, :nodes => [fqdn]) { |mco| mco.ping }
    failed = (rsps.size != 1 || rsps[0][:statuscode] != 0 || rsps[0][:data][:pong].nil?)

    if failed
      return ping(fqdn, attempts - 1) if attempts > 1

      if rsps.size == 0
        logger(Logger::DEBUG) { "no response to mco ping from #{fqdn}" }
      else
        logger(Logger::WARN) { "failed to mco ping #{fqdn}: #{rsps[0][:statusmsg]}" } unless rsps[0][:statuscode] == 0
      end
      return nil
    end

    rsps[0][:data][:pong]
  end

  def get_inventory(fqdns, ignore_missing = true)
    responses = mco_client("rpcutil", :timeout => 30, :nodes => fqdns) { |mco| mco.inventory }
    failed_to_respond = fqdns - responses.map { |r| r[:sender] }
    failed_to_respond.each { |fqdn| logger(ignore_missing ? Logger::WARN : Logger::ERROR) { "No inventory response from #{fqdn}" } }
    fail "Some machines did not respond to mco inventory" unless ignore_missing || failed_to_respond.empty?

    failures = responses.select { |r| r[:statuscode] != 0 }.map { |r| "#{r[:sender]}: #{r[:statusmsg]}" }
    fail "failed to perform mco inventory on some hosts:\n  #{failures.join('\n  ')}" unless failures.empty?

    responses.map do |resp|
      [resp[:sender], {
        :facts   => resp[:data][:facts],
        :classes => resp[:data][:classes],
        :agents  => resp[:data][:agents]
      }]
    end.to_h
  end
end
