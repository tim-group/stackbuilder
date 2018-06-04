require 'stackbuilder/stacks/namespace'
require 'stackbuilder/support/mcollective'

module Support
  class MCollectiveRpcutil
    include Support::MCollective

    def ping(fqdn)
      responses = mco_client("rpcutil", :nodes => [fqdn]) { |mco| mco.ping }
      fail "no response from mco ping" unless responses.size == 1
      response = responses.first
      fail "failed to mco ping #{vm_fqdn}: #{response[:statusmsg]}" unless response[:statuscode] == 0
      response[:data][:pong]
    end

    def get_inventory(fqdns, ignore_missing = true)
      responses = mco_client("rpcutil", :nodes => fqdns) { |mco| mco.inventory }
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
end
