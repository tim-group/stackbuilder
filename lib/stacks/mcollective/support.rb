require 'mcollective'

module Stacks
  module MCollective
    module Support
      attr_accessor :scope

      class MCollectiveFabricRunner
        include ::MCollective::RPC
        def provision_vms(specs)
          mc = rpcclient("provisionvm")
          return mc.provision_vms(:specs=>specs)
        end
      end
 
      def create_fabric_runner
	return MCollectiveFabricRunner.new
      end

      def mcollective_local(options={}, &block)
        block.call()
      end

      def mcollective_fabric(options={}, &block)
        read,write = IO.pipe
        pid = fork do
          runner = create_fabric_runner(options)
          result = nil
	  exception = nil
          begin
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
