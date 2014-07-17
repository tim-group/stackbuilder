require 'net/http'
require 'json'
require 'resolv'

module Support
  module Nagios

    class Helper
      def initialize(options)
        @helper = options[:helper] ||  Nagios::HttpHelper.new(options)
      end

      def schedule_downtime(fqdn, duration=600)
        @helper.schedule_downtime(fqdn, duration)
      end

      def cancel_downtime(fqdn)
        @helper.cancel_downtime(fqdn)
      end

    end

    class HttpHelper
      def initialize(options)
        default_nagios_servers = ['antarctica.mgmt.oy.net.local:5152', 'australia.mgmt.pg.net.local:5152']
        @nagios_servers = options[:nagios_servers]  || default_nagios_servers
      end

      def http_request(url, body, initheader)
        uri = URI.parse(URI.encode(url))
        request = Net::HTTP::Post.new(uri.path, initheader)
        request.body = body
        http = Net::HTTP.new(resolv_host_for_uri(uri), uri.port)
        http.use_ssl = true if uri.scheme == 'https'
        response = http.start  do |http|
          http.request(request)
        end
        response
      end

      def resolv_host_for_uri(uri)
        begin
          Resolv.getaddress uri.host
        rescue Exception => e
          raise e
        end
        uri.host
      end

      def process_response(response)
        result = nil
        begin
          if response.code !='200'
            result = "Failed: HTTP response code was #{response.code}"
          else
            json = JSON.parse(response.body)
            if json['success']
              result = "OK: #{json['content']}"
            else
              result = "Failed: #{json['content']}"
            end
          end
          rescue Exception => e
            result = "Failed: #{e} #{e.backtrace}"
        end
        result
      end

      def modify_downtime(action, fqdn, duration=nil)
        body = { "host" => fqdn }
        body["duration"] = duration unless duration.nil?
        header = {'Content-Type' =>'application/json' }

        responses = {}
        @nagios_servers.each do |server|
          url = "http://#{server}/#{action}_downtime"
          response = http_request(url, body.to_json, header)
          responses[server] = process_response(response)
        end
        responses
      end

      def schedule_downtime(fqdn, duration=600)
        modify_downtime('schedule', fqdn, duration)
      end

      def cancel_downtime(fqdn)
        modify_downtime('cancel', fqdn)
      end
    end
  end
end

