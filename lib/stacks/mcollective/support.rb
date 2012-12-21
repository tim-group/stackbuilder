$LOAD_PATH.unshift('/opt/puppetroll/lib/')

require 'mcollective'
require 'puppetroll'
require 'puppetroll/client'

module Stacks
  module MCollective
    module Support
      attr_accessor :scope

      class MCollectiveFabricRunner
        include ::MCollective::RPC
        def initialize(options)
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

          @options = ::MCollective::Util.default_options
        end

        def new_client(name, nodes=nil)
          client = rpcclient(name, :options=>@options)
          client
        end

        def provision_vms(specs)
          mc = new_client("provisionvm")
          return mc.provision_vms(:specs=>specs)
        end

        def ping()
          client = ::MCollective::Client.new(@options[:config])
          client.options = @options
          responses = []
          client.req("ping", "discovery") do |resp|
            responses << resp[:senderid]
          end
          return responses
        end

        def wait_for_ping(nodes)
          found = false
          result = nil
          retries = 60

          pp nodes

          retries.times do |i|
            result = ping()
            pp result
            if nodes.to_set.subset?(result.to_set)
              found = true
              break
            end
          end
          raise "timeout out waiting for hosts to be available" unless found
          return result
        end

        def run_nrpe(nodes=nil)
          mc = new_client("nrpe", :nodes=>nodes)
          mc.runallcommands.each do |resp|
            nrpe_results[resp[:sender]] = resp
          end
        end

        def puppetd(nodes=nil)
          mc = new_client("puppetd", nodes=> nodes)

          pp mc.status()
        end

        def run_puppetroll(nodes=nil)
          mc = new_client("puppetd", nodes=> nodes)
          engine = PuppetRoll::Engine.new({:concurrency=>5}, [], nodes, PuppetRoll::Client.new(nodes, mc))
          engine.execute()
          return engine.get_report()
        end

        def puppetca_sign(hostname)
          mc = new_client("puppetca")
          return mc.sign(:certname => hostname)[0]
        end

      end

      def create_fabric_runner(options)
        return MCollectiveFabricRunner.new(options)
      end

      def mcollective_fabric(options={}, &block)
        read,write = IO.pipe
        pid = fork do
          begin
            runner = create_fabric_runner(options)
            result = nil
            exception = nil
            result = runner.instance_eval(&block)
          rescue Exception=>e
            exception = e
          end
          Marshal.dump({:result=>result, :exception=>exception}, write)
        end
        write.close
        serialized_result = read.read
        result = Marshal.load(serialized_result)
        Process.waitpid(pid)
        raise result[:exception] unless result[:exception]==nil
        result[:result]
      end
    end
  end
end
