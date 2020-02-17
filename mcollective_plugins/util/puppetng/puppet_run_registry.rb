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
module Util
module PuppetNG

# This class just loads the report files from disk and adds a few fields.

class PuppetRunRegistry
  def initialize(manager, report_dir)
    @manager = manager
    @report_dir = report_dir
  end

  def load_from_disk(runid)
    # protect against directory traversal.
    runid = File.basename(runid)
    filename = File.join(@report_dir, "#{runid}.json")
    if File.exists?(filename)
      begin
      	data = JSON.load(File.open(filename, "r").read)
      rescue Exception => e
        raise "Failed to read/parse #{filename}: " + e.message
      end
      # mcollective uses symbolized keys, parsed JSON does not. so convert.
      data.keys.each do |key|
        data[key.to_sym] = data.delete(key)
      end
      # time since the update in the report, based on our own clock.
      data[:update_age] = Time.now.to_i - data[:update_time] unless data[:update_time].nil?
      # report if the PID in the report is still running. can be useful to detect
      # non-starts or crashes in the daemon.
      data[:pid_active] = @manager.has_process_for_pid?(data[:pid]) unless data[:pid].nil?
      return data
    end
  end
end

end # PuppetNG Module
end # Util Module
end # MCollective Module
