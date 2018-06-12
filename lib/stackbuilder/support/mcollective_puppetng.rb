require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

module Support
  class MCollectivePuppetng
    include Support::MCollective

    def run_puppet(host_fqdns, tags = [])
      logger(Logger::INFO) { "Triggering puppet runs on #{host_fqdns.join(', ')}." }

      results = mco_client("puppetng", :nodes => host_fqdns) do |mco|
        run_id = "stackbuilder_#{Time.now.to_i}"
        responses = mco.run(:runid => run_id, :tags => tags.empty? ? nil : tags.join(','))
        return responses if responses.count { |r| r[:statuscode] == 0 } < host_fqdns.size

        loop do
          responses = mco.check_run(:runid => run_id)
          finished_hosts = responses.
                           select { |r| r[:statuscode] == 0 && r[:data][:state] != 'waiting' && r[:data][:state] != 'running' }.
                           map { |r| r[:sender] }
          break if finished_hosts.size == host_fqdns.size
          logger(Logger::DEBUG) { "Waiting for puppet runs to complete on #{(host_fqdns - finished_hosts).join(', ')}." }
          sleep 5
        end

        responses
      end

      hosts_with_results = results.reject { |r| r[:data][:state].nil? }.map { |r| r[:sender] }
      failed_to_trigger_on = host_fqdns - hosts_with_results
      unless failed_to_trigger_on.empty?
        logger(Logger::FATAL) { "Failed to trigger puppet on #{failed_to_trigger_on.join(', ')}" }
        fail "puppet runs could not be triggered"
      end

      failed_runs = results.reject { |r| r[:data][:state] == 'success' }
      return if failed_runs.empty?

      failed_runs.each { |run| logger(Logger::FATAL) { "Puppet run failed on #{run[:sender]}:\n  #{run[:data][:errors].join("\n  ")}" } }
      fail "puppet runs failed"
    end
  end
end
