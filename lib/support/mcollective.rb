$LOAD_PATH.unshift('/opt/puppetroll/lib/')

require 'support/forking'
require 'mcollective'
require 'puppetroll'
require 'puppetroll/client'

module Support
  module MCollective
    include ::Support::Forking

    class MCollectiveFabricRunner
      def initialize(options)
        @rpc = MCollectiveRPC.new
        @options = options
        @mco_options = ::MCollective::Util.default_options

        @mco_options[:timeout] = options[:timeout] if options.has_key?(:timeout)
      end

      def new_client(name)
        client = @rpc.rpcclient(name, :options => @mco_options)
        if @options.has_key?(:fabric)
          apply_fabric_filter client, @options[:fabric]
        end
        client
      end

      def apply_fabric_filter(mco, fabric)
        if fabric == "local"
          mco.identity_filter `hostname --fqdn`.chomp
        else
          mco.fact_filter "domain", "mgmt.#{fabric}.net.local"
        end
      end

      def configure_mco
        # dump hard earnt knowledge about how to configure mcollective programmatically, TODO: test and tidy
        broker = options[:broker]
        timeout = options[:timeout]
        config_file = options[:config_file] || "/etc/mcollective/client.cfg"
        key = options[:key] || nil

        ENV.delete('MCOLLECTIVE_SSL_PRIVATE') unless key.nil?
        ENV.delete('MCOLLECTIVE_SSL_PUBLIC') unless key.nil?

        @config = ::MCollective::Config.instance()
        @config.loadconfig(config_file)

        unless key.nil?
          @config.pluginconf["ssl_server_public"] = "/store/stackbuilder/framework/client/server-public.pem"
          @config.pluginconf["ssl_client_public"] = "/store/stackbuilder/framework/client/seed.pem"
          @config.pluginconf["ssl_client_private"] = "/store/stackbuilder/framework/client/seed-private.pem"
        end
        @config.pluginconf["stomp.pool.host1"] = broker unless broker.nil?
        @config.pluginconf["timeout"] = timeout unless timeout.nil?
      end
    end

    class MCollectiveRPC
      include ::MCollective::RPC
    end

    private
    def create_fabric_runner(options)
      return MCollectiveFabricRunner.new(options)
    end

    def mco_client(name, options={}, &block)
      return async_mco_client(name, options, &block).value
    end

    def async_mco_client(name, options={}, &block)
      async_fork_and_return do
        runner = create_fabric_runner(options)
        client = runner.new_client(name)
        nodes = options[:nodes] || []
        nodes.empty? ? client.discover(): client.discover(:nodes => nodes)
        block.call(client)
        client.disconnect
      end
    end
  end
end
