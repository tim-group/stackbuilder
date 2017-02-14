require 'net/http'
require 'json'
require 'resolv'
require 'stackbuilder/support/callback'
require 'stackbuilder/stacks/namespace'

module Support
  module Nagios
    class Service
      def initialize(options = {})
        @service = options[:service] || Nagios::Service::Http.new(options)
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
    end

    class Service::Http
      def initialize(options)
        ## FIXME: This does not belong here, but we dont know where it should go
        default_nagios_servers = {
          'oy' => ['oy-nagios-001.mgmt.oy.net.local'],
          'pg' => ['pg-nagios-001.mgmt.pg.net.local']
        }
        default_api_port = 5152
        @nagios_servers = options[:nagios_servers] || default_nagios_servers
        @nagios_api_port = options[:nagios_api_port] || default_api_port
      end

      def http_request(url, body, initheader)
        uri = URI.parse(URI.encode(url))
        request = Net::HTTP::Post.new(uri.path, initheader)
        request.body = body
        http = Net::HTTP.new(resolv_host_for_uri(uri), uri.port)
        http.use_ssl = true if uri.scheme == 'https'
        response = http.start { |h| h.request(request) }
        response
      end

      def resolv_host_for_uri(uri)
        begin
          Resolv.getaddress uri.host
        rescue StandardError => e
          raise e
        end
        uri.host
      end

      def process_response(response)
        result = nil
        begin
          if response.code != '200'
            result = "Failed: HTTP response code was #{response.code}"
          else
            json = JSON.parse(response.body)
            if json['success']
              result = "OK: #{json['content']}"
            else
              result = "Failed: #{json['content']}"
            end
          end
          rescue StandardError => e
            result = "Failed: #{e} #{e.backtrace}"
        end
        result
      end

      def get_nagios_servers_for_fabric(fabric)
        return @nagios_servers[fabric] rescue nil
      end

      def modify_downtime(action, machine, duration = nil)
        body = { "host" => machine.mgmt_fqdn }
        body["duration"] = duration unless duration.nil?
        header = { 'Content-Type' => 'application/json' }
        nagios_servers = get_nagios_servers_for_fabric(machine.fabric)
        return "skipping #{machine.hostname} - No nagios server found for #{machine.fabric}" if nagios_servers.nil? || nagios_servers.empty?
        ret = []
        nagios_servers.each do |nagios_server|
          url = "http://#{nagios_server}:#{@nagios_api_port}/#{action}_downtime"
          response = http_request(url, body.to_json, header)
          ret << "#{nagios_server} = #{process_response(response)}"
        end
        ret.join(',')
      end

      def schedule_downtime(machine, duration = 600)
        modify_downtime('schedule', machine, duration)
      end

      def cancel_downtime(machine)
        modify_downtime('cancel', machine)
      end
    end
  end
end
