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

metadata :name => "puppetng",
         :description => "Agent for running puppet with many checks on its progress",
         :author => "IG Group",
         :license => "Apache 2.0",
         :version => "1.0.0",
         :url => "http://www.ig.com/",
         :timeout => 20

requires :mcollective => "2.2.1"

action "check_run", :description => "Check the status of a run" do
    display :always

    input :runid,
          :prompt      => "Run ID",
          :description => "Identifier for the puppet run",
          :type        => :string,
          :validation  => '.*',
          :optional    => false,
          :maxlength   => 50

    output :state,
           :description => "Status of the run",
           :display_as  => "run state"

    output :report_errors,
           :description => "Errors from run report",
           :display_as  => "report errors"

    output :errors,
           :description => "errors",
           :display_as  => "Errors from run"

    output :summary,
           :description => "Report summary",
           :display_as  => "report summary",
           :optional    => true

    output :method,
           :description => "Method used",
           :display_as  => "method used",
           :optional    => true

    output :expired_executions,
           :description => "Execution expired retries",
           :display_as  => "expired retries",
           :optional    => true

    output :pid,
           :description => "PID for igpuppet agent",
           :display_as  => "PID",
           :optional    => true

    output :pid_active,
           :description => "Is PID running?",
           :display_as  => "PID active",
           :optional    => true

    output :noop,
           :description => "Is this a noop run",
           :display_as  => "noop run",
           :optional    => true

    output :tags,
           :description => "Tags to pass to the puppet agent",
           :display_as  => "tags",
           :type        => :string,
           :validation  => '.*',
           :maxlength   => 50,
           :optional    => true

    summarize do
        aggregate summary(:state)
    end
end

action "run", :description => "Invoke puppet" do
    input :runid,
          :prompt      => "Run ID",
          :description => "Identifier for the puppet run",
          :type        => :string,
          :validation  => '.*',
          :optional    => false,
          :maxlength   => 50

    input :noop,
          :prompt      => "Noop",
          :description => "Do a Puppet dry run",
          :type        => :boolean,
          :optional    => true
end
