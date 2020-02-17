# Copyright IG Group
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module MCollective
  module Agent
    class Puppetng<RPC::Agent
      # test that we can load puppet and the util/puppetng code, otherwise
      # do not activate the agent because it won't work.
      activate_when do
        begin
          require 'puppet'
          require 'mcollective/util/puppetng'
          true
        rescue Exception => e
          Log.error(e)
          false
        end
      end

      def startup_hook
        # get where to write report file to, to pass into PuppetRunRegistry
        @report_dir = @config.pluginconf.fetch("puppetng.report_dir", "/tmp")

        # the PuppetAgentMgr class provides some functions for checking on puppet
        # which work on puppet 2 or puppet 3.
        @puppet_agent = MCollective::Util::PuppetAgentMgr.manager(nil, "puppet")

        # PuppetRunRegistry loads the JSON reports off the disk for check_run requests
        @registry = MCollective::Util::PuppetNG::PuppetRunRegistry.new(@puppet_agent, @report_dir)
      end

      # The run action simply starts the daemon process in the background. The daemon
      # location is configurable by puppetng.agent_path in server.cfg. The runid
      # from the requester is passed in as the only argument, plus --daemonize flag and
      # optionally --noop.
      
      action "run" do
        runid = request[:runid]
        agent_path = @config.pluginconf.fetch("puppetng.agent_path", "/usr/local/sbin/puppetng_agent")
        cmd = "#{agent_path} #{runid} --daemonize"
        cmd += " --noop" if request[:noop] == true
        cmd += " --tags #{request[:tags]}" unless request[:tags].nil?
        Log.debug("running puppetng daemon: #{cmd}")
        system(cmd)
      end


      action "check_run" do
        runid = request[:runid]

        # reads from file named <runid>.json under dir configurable by puppetng.report_dir configurable
        report = @registry.load_from_disk(runid)

        unless report.nil?
          # the report was read, so merge it into the response hash.
          reply.data.merge!(report)
        else
          # nil probably means the run was never recorded for some reason. respond with state :not_found.
          reply[:state] = :not_found
        end
      end
    end
  end
end
