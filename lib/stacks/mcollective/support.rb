$LOAD_PATH.unshift('/opt/puppetroll/lib/')

require 'mcollective'
require 'puppetroll'
require 'puppetroll/client'

module Stacks
  module MCollective
    module Support
      class MCollectiveFabricRunner
        def initialize(options)
          @rpc = MCollectiveRPC.new
          @options = options
          @mco_options = ::MCollective::Util.default_options
        end

        def new_client(name, nodes=nil)
          client = @rpc.rpcclient(name, :options => @mco_options)
          if @options.has_key?(:fabric)
            apply_fabric_filter client, @options[:fabric]
          end
          yield client
        end

        def apply_fabric_filter(mco, fabric)
          if fabric == "local"
            mco.identity_filter `hostname --fqdn`.chomp
          else
            mco.fact_filter "domain","mgmt.#{fabric}.net.local"
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
      
      def create_fabric_runner(options)
        return MCollectiveFabricRunner.new(options)
      end

      ## TODO: factor this out this is nothing to do with mco
      ## just forking and future foo
      class Future
        def initialize(&block)
          @block = block
        end

        def value
          return @block.call
        end
      end

      def mcollective_fabric(options={}, &block)
        async_mcollective_fabric(options, &block).value
      end

      def async_mcollective_fabric(options={}, &block)
        read,write = IO.pipe
        pid = fork do
          begin
            runner = create_fabric_runner(options)
            result = nil
            exception = nil
            result = block.call(runner)
          rescue Exception=>e
            exception = e
          end
          Marshal.dump({:result=>result, :exception=>exception}, write)
        end
        write.close

        Future.new do
          serialized_result = read.read
          Process.waitpid(pid)
          result = Marshal.load(serialized_result)
          raise result[:exception] unless result[:exception]==nil
          result[:result]
        end
      end
    end
  end
end
