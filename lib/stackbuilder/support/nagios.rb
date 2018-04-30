require 'stackbuilder/stacks/namespace'
require 'stackbuilder/support/callback'
require 'stackbuilder/support/mcollective'

module Support
  module Nagios
    class Service
      def initialize(options = {})
        @service = options[:service] || Nagios::Service::MCollective.new
      end

      def schedule_downtime(machines, duration = 600, &block)
        callback = Support::Callback.new(&block)
        machines.each do |machine|
          response = @service.schedule_downtime(machine, duration)
          callback.invoke :success, :machine => machine.hostname, :result => response
        end
      end

      def cancel_downtime(machines, &block)
        callback = Support::Callback.new(&block)
        machines.each do |machine|
          response = @service.cancel_downtime(machine)
          callback.invoke :success, :machine => machine.hostname, :result => response
        end
      end

      def register_new_machines(machines)
        sites = machines.map(&:fabric).uniq
        logger(Logger::INFO) { "running puppet on nagios servers (in #{sites}) so they will discover this node and include in monitoring" }

        fqdn_filter = "fqdn=/mgmt.(#{sites.join('|')}).net.local/"
        system('mco', 'puppetng', 'run', '--concurrency', '5', '--with-fact', fqdn_filter, '--with-class', 'nagios')
      end
    end

    class Service::MCollective
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
  end
end
