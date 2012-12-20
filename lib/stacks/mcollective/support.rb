require 'mcollective'

module Stacks
  module MCollective
    module Support
      attr_accessor :scope

      class MCollectiveFabricRunner
        include ::MCollective::RPC
        def provision_vms(specs)
          require 'yaml'
          yml = YAML.load IO.read('/store/stackbuilder/cas/vms.yaml')
          mc = rpcclient("provisionvm")
          return mc.provision_vms(:specs=>yml)
        end
      end

      def mcollective_local(&block)
        return MCollectiveRunner.new
      end

      def mcollective_fabric(&block)
        read,write = IO.pipe
        pid = fork do
          runner = MCollectiveFabricRunner.new
          result = runner.instance_eval(&block)
          Marshal.dump(result,write)
        end
        write.close
        result = Marshal.load(read.read)
        Process.waitpid(pid)
        raise "@@@" unless  $?.exitstatus == 0
        result
      end
    end
  end
end
