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

MAX_SUMMARY_FAILURES = 6
MAX_REPORT_FAILURES = 10

# This class does most of the work, kicking off a puppet run, watching it
# and writing out reports of progress to a JSON file.
class ManagedPuppetRun
  attr_accessor :id, :errors, :report_errors, :state, :noop, :tags

  # mostly get configurables for later use
  def initialize(manager, id)
    @noop = false
    @config = MCollective::Config.instance
    # we're running in a standalong process not in mcollective, so the config
    # probably needs loading.
    @config.loadconfig("/etc/mcollective/server.cfg") unless @config.configured == true
    @timeout = @config.pluginconf.fetch("puppetng.timeout", 60 * 20).to_i
    @apply_wait_max = @config.pluginconf.fetch("puppetng.apply_wait_max", 45).to_i
    @report_wait_max = @config.pluginconf.fetch("puppetng.report_wait_max", 120).to_i
    @expired_execution_retries = @config.pluginconf.fetch("puppetng.expired_execution_retries", 1).to_i
    @report_dir = @config.pluginconf.fetch("puppetng.report_dir", "/tmp")

    @state = :unknown
    @manager = manager
    # prevent directory traversal in runid provided causing writes to files outside report_dir.
    @id = File.basename(id)
    @expired_executions = 0
    @errors = []
    @report_errors = []
    @lastrunreport_file = Puppet[:lastrunreport]
    @lastrunsummary_file = Puppet[:lastrunfile]
  end

  def lastrun
    Integer(get_summary["time"].fetch("last_run", 0))
  end

  # sometimes I've seen puppet writes "false" to the YAML file for a short time.
  # if what is loaded is not a hash, keep retrying up to puppetng.max_summary_failures
  # with 1 second delay.
  def get_summary
    failures = 0
    while failures < @config.pluginconf.fetch("puppetng.max_summary_failures", MAX_SUMMARY_FAILURES).to_i
      begin
        yaml = YAML.load_file(@lastrunsummary_file)
        if yaml.is_a?(Hash)
          return yaml
        end
      rescue
      end
      failures += 1
      sleep 1
    end
    #TODO: more specific exception
    raise "failed to load summary YAML"
  end

  # similar to get_summary. we check it has a "logs" field.
  def get_report
    failures = 0
    while failures < @config.pluginconf.fetch("puppetng.max_report_failures", MAX_REPORT_FAILURES).to_i
      begin
        yaml = YAML.load_file(@lastrunreport_file)
        if yaml.respond_to?("logs")
          return yaml
        end
      rescue
      end
      failures += 1
      sleep 1
    end
    #TODO: mpore specific exception
    raise "failed to load report YAML"
  end

  # mtime of lastrunreport, written after summary
  def lastrunreport_mtime
    File.stat(@lastrunreport_file).mtime.to_i
  end

  # mtime of summary
  def lastrunsummary_mtime
    File.stat(@lastrunsummary_file).mtime.to_i
  end

  # If puppet daemon is not running, we run puppet in the foreground (in our daemon).
  # So we can make use of the detailed exitcodes puppet provides as well as the other
  # checks. See below from man page:
  #
  #* --detailed-exitcodes:
  #  Provide transaction information via exit codes. If this is enabled, an exit
  #  code of '2' means there were changes, an exit code of '4' means there were
  #  failures during the transaction, and an exit code of '6' means there were both
  #  changes and failures.

  def puppet_detailed_exit_code_indicates_error?(ec)
    return (ec == 4 or ec == 6 or ec == 1)
  end

  # Run puppet in foreground and check exit code.
  def foreground_run
    puppet_path = @config.pluginconf.fetch("puppetng.puppet_path", "/usr/bin/puppet")
    cmd = "#{puppet_path} agent --test --detailed-exitcodes"
    cmd += " --noop" if @noop == true
    cmd += " --tags #{@tags}" unless @tags.nil?
    system(cmd)
    ec = $?
    if puppet_detailed_exit_code_indicates_error?(ec)
      @errors << "puppet exit code #{ec} indicates a failure."
    end
  end

  def daemon_run
    prevrun = lastrun
    start_time = Time.now.to_i
    apply_start_time = 0
    signal_retries = 0
    tick = 0

    # SIGUSR1 is used, so no way to tell daemon we want noop.
    if @noop == true
      raise "cannot do noop in daemon mode"
    end

    unless @tags.nil?
        raise "cannot pass tags in daemon mode"
    end

    # send SIGUSR1
    @manager.signal_running_daemon

    # check the lastrun field in the summary YAML every second. if it increases, a
    # run probably completed.
    while lastrun <= prevrun
      since_start = Time.now.to_i - start_time
      is_applying = @manager.applying?

      # record when it started applying
      if apply_start_time <= 0 and is_applying
        apply_start_time = Time.now.to_i
      end

      if since_start > @timeout
        raise "timeout waiting for run to complete."
#      elsif since_start > 20 and apply_start_time <= 0 and signal_retries < 3
#        @manager.signal_running_daemon
#        signal_retries += 1
      # we signaled the daemon but it didn't start applying after @apply_wait_max seconds 
      # sometimes this is the cause: https://projects.puppetlabs.com/issues/4624
      elsif since_start > @apply_wait_max and apply_start_time <= 0
        raise "the agent didn't start applying after #{@apply_wait_max} seconds."
      end

      # every 5 iterations just write out to say we're still going
      write_report if tick % 5 == 0

      tick += 1
      sleep 1
    end

    run_done = Time.now.to_i

    # the report (to detect errors) was not written out after run completed.
    # we need this to report back errors, so consider it an error itself.
    while lastrunreport_mtime < lastrunsummary_mtime
      if Time.now.to_i - run_done > @report_wait_max
        raise "report not written #{@report_wait_max} seconds after run completes."
      end
      sleep 1
    end
  end

  # if a run was going when we started, it could be an old version of the catalog.
  # we need to wait for it to stop.
  def wait_for_not_applying
    start = Time.now.to_i
    tick = 0

    while @manager.applying?
      @state = :waiting

      write_report if tick % 5 == 0

      if Time.now.to_i - start > (60 * 8)
         raise "timed out waiting for an existing apply to finish."
      end

      tick += 1
      sleep 1
    end
  end

  # check the various resource fields for indications of error
  def check_summary_for_errors(summary)
    if summary.has_key?("resources")
      resources = summary["resources"]

      failed_to_restart = resources["failed_to_restart"]
      if failed_to_restart.nil?
        @errors << "failed to restart count not in summary."
      elsif failed_to_restart > 0
        @errors << "#{failed_to_restart} resources failed to restart."
      end

      failed = resources["failed"]
      if failed.nil?
        @errors << "failed resources count not in summary."
      elsif failed > 0
        @errors << "#{failed} failed resources."
      end

      total = resources["total"]
      # this happens when execution expired sometimes. 
      if total.nil?
        @errors << "total resources count not in summary."
      elsif total == 0
        @errors << "there were zero total resources in the run summary, which suggests something went wrong."
      end      
    else
      @errors << "no resources information."
    end

    # failure events are usually failed resourced, but sometimes aren't.
    # we record these if there aren't already failed resources.
    if summary.has_key?("events")
      failure = summary["events"]["failure"]
      if failure.nil?
        @errors << "no failure count in summary events."
      elsif failure > 0 and failed == 0
        @errors << "#{failure} failure events."
      end
    else
      @errors << "no events in summary."
    end

    @errors.length
  end

  # filter the last_run_report.yaml to get errors. if there are any, record this
  # as one of our own failure messages.
  def check_report_for_errors(report)
    @report_errors = report.logs.reject { |x| x.level != :err }.map { |x| x.message }
    if @report_errors.length > 0
      @errors << "report contains #{@report_errors.length} errors"
    end
  end

  # dump various fields in this class into a hash, to go in the JSON report.
  def get_status
    status = {}

    status[:noop] = @noop
    status[:tags] = @tags unless @tags.nil?
    status[:state] = @state
    status[:report_errors] = @report_errors
    status[:errors] = @errors
    status[:expired_executions] = @expired_executions
    status[:update_time] = Time.now.to_i
    status[:pid] = Process.pid

    unless @backtrace.nil?
      status[:backtrace] = @backtrace
    end

    unless @summary.nil?
      status[:summary] = @summary
    end

    unless @method.nil?
      status[:method] = @method
    end

    status
  end

  # where to store out report. the report dir plus a JSON file named by our runid.
  # @id is protected against directory traversal.
  def report_file
    File.join(@report_dir, "#{@id}.json")
  end

  # atomic_file is used to write to a tmp file and overwrite the report.
  # ensuring half written reports are not consumed.
  def write_report
    @manager.atomic_file(report_file) do |file|
      file.write(JSON.pretty_generate(get_status))
    end
  end

  # detect expired execution from report errors.
  def expired_execution?
    @report_errors.each do |err|
      if err =~ /execution expired$/
        return true
      end
    end
    return false
  end

  # clear errors, for if we want to retry
  def clear_errors
    @errors = []
    @report_errors = []
  end

  def start
    begin 
      wait_for_not_applying

      # our puppet agents randomly disable themselves, so we reenable them.
      if @manager.disabled?
        reenable = @config.pluginconf.fetch("puppetng.reenable", false)
        reenable = true if reenable == "true"
        if reenable 
          @manager.enable!
        else
          raise "host is disabled"
        end
      end

      @state = :running

      if @manager.idling?
        @method = :daemon
        write_report
        daemon_run
      else
        @method = :foreground
        write_report
        foreground_run
      end

      @summary = get_summary
      @report = get_report

      check_report_for_errors(@report)
      check_summary_for_errors(@summary)

      if expired_execution? and @expired_executions < @expired_execution_retries
        clear_errors
        @expired_executions += 1
        return start
      end
      # some of the functions called use exceptions to stop. we take the message
      # and record it as a failure.
    rescue => ex
      @errors << ex
      # record backtrace in the report, useful for troubleshooting agent failures.
      if ex.respond_to?(:backtrace)
          bt = ex.backtrace
          unless bt.nil?
              @backtrace = bt.join("\n")
          end
      end
    end

    # any errors means we failed
    if @errors.length > 0
      @state = :failed
    else
      @state = :success
    end

    # write the final report.
    write_report
  end

  def start_in_thread
    write_report
    Thread.new do
      start
    end
  end
end

end # PuppetNG Module
end # Util Module
end # MCollective Module
