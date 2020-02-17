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

# the colorize gem, with a few small improvements for disabling color
require 'mcollective/util/puppetng/colorize'

module MCollective
module Util
module PuppetNG

DISPLAY_PROGRESS_MAX_HOSTS = 10
DISPLAY_PROGRESS_HOSTS_PREVIEW = 4
TIME_BEFORE_UNRESPONSIVE = 30
TICKS_BEFORE_UNRESPONSIVE = 4

# time string used to prefix log lines
def logtime
  Time.now.strftime("%H:%M:%S")
end

# This class inherits from Hash.
# We store instances of McoHost classes as the value
# and use the hostname string as the key.

class HostCollection < Hash
  attr_accessor :mc, :serial, :observers, :runid
  include MCollective::Util::PuppetNG

  def initialize(mc, runid)
    @mc = mc
    @runid = runid
    @serial = 0

    @observers = []
  end

  # When a host changes state, it notifies the collection it is part of.
  # This is because the collections knows the various counts of states,
  # which we would like to print to indicate progress with a message
  # about this host.

  def run_notify(state, host)
    n_succeed = succeeded.length
    n_failed = failed.length
    n_done = n_succeed + n_failed

    if state == :failed
      puts "#{logtime} #{host.hostname} failed :: #{n_done}/#{length} (success: #{n_succeed}, failed: #{n_failed})".red
      host.print_failures
    elsif state == :success
      rsummary = host.resources_summary
      print "#{logtime} #{host.hostname} success".green
      unless rsummary.nil?
        print " (#{rsummary})".green
      end
      print " :: "
      puts "#{n_done}/#{length} (success: #{n_succeed}, failed: #{n_failed})".green
    end

    @observers.each { |o| o.on_node_update(self, host) if o.respond_to?(:on_node_update) }
  end

  # We usually want to work with a sorted collection collection.
  
  def values
    super.sort
  end

  def incompletes
    values.reject { |h| h.state == :failed or h.state == :success }
  end

  # Hosts which have not had run called on yet.
  def pending
    incompletes.reject { |h| h.run_time > 0 }
  end

  # The opposite, incomplete hosts which HAVE been run.
  def local_running
    incompletes.select { |h| h.run_time > 0 }
  end

  def local_running_hostnames
    local_running.map { |h| h.hostname }
  end

  # All hosts in successful state.
  def succeeded
    values.select { |h| h.state == :success }
  end

  # All hosts in unsuccessful state
  def failed
    values.select { |h| h.state == :failed }
  end

  # Used as while condition in the main loop. Is there work to do?
  def has_incomplete?
    incompletes.length > 0
  end

  # A one-line string summary of states.
  def get_summary
    return "total = #{length}, failed = #{failed.length}, success = #{succeeded.length}."
  end

  # After each check_run update, we check for hosts which have not responded in this loop.
  def check_for_unresponsive
    local_running.each do |h|
      # see McoHost.is_unresponsive? - it checks number of failed updates and time it has
      # been missing.
      if h.is_unresponsive?
        h.mark_failed "host stopped responding."
      # Give up to 10 seconds after start before taking notice of the
      # not_found state, ot that the agent process is not running.
      elsif h.run_time > 0 and Time.now.to_i - h.run_time > 10
        if h.state == :not_found
          h.mark_failed "run #{@runid} not found on agent." 
        # the agent lets us know if the PID which started a run is actually running.
        # if the run is incomplete and the monitor is not running, it probably failed.
        elsif !h.is_active?
          h.mark_failed "agent process responsible for monitoring the puppet run stopped."
        end
      end
    end
  end
end

class McoHost
  attr_accessor :hostname, :latest, :serial, :update_time, :collection, :run_time
  attr_accessor :ticks_before_unresponsive, :time_before_unresponsive, :local_error

  include MCollective::Util::PuppetNG
  include Comparable

  def initialize(hostname, collection)
    @run_time = -1
    @hostname = hostname
    # used for notifications
    @collection = collection
    @serial = collection.serial
    @update_time = -1

  end

  # string summarizing the run
  def resources_summary
    if !@latest.nil? and !@latest[:summary].nil? and !@latest[:summary]["resources"].nil?
      resources = @latest[:summary]["resources"]
      buf = "#{resources["total"]} total resources"
      if resources["changed"] > 0
        buf += ", #{resources["changed"]} changed resources"
      end
      return buf
    end
    return ""
  end

  # so the collection can sort by hostname
  def <=>(other)
    hostname <=> other.hostname
  end

  def update(response)
    # setting our serial to the global serial prevents it being picked
    # up in a check_unresponive / is_unresponsive? check.
    @serial = @collection.serial

    if response[:statuscode] == 0
      @update_time = Time.now.to_i

      lastupdate = @latest
      @latest = response[:data]


      @collection.run_notify(state, self)

      # the expired_executions count incremented since the last update.
      # notify the application user that this happened.
      if !lastupdate.nil? and !lastupdate[:expired_executions].nil? and !@latest[:expired_executions].nil?
        if @latest[:expired_executions] > lastupdate[:expired_executions] and !is_complete?
          puts "#{logtime} #{@hostname} gave \"execution expired\" error. will retry.".yellow
        end
      end
    else
      mark_failed "failed update: #{response[:statusmsg]}"
      puts response.inspect
    end
  end

  # Complete is either success or failure, nothing else.
  def is_complete?
    s = state
    return (s == :failed or s == :success)
  end

  # the pid_active field from a response, or nil if we don't have one yet.
  def is_active?
    if !@latest.nil? and !@latest[:pid_active].nil?
      return @latest[:pid_active]
    end
    nil
  end

  # for checking if the host did not respond to our run request.
  def check_run_failed
    if @serial != @collection.serial and run_time > 0
      mark_failed "no response to run request."
    end
  end

  # the host did respond to our run request, so record this using the serial.
  # also check for failure in that response.
  def run_init(response)
    if response[:statuscode] != 0
      @local_error = "run request failed: #{response[:statusmsg]}"
    end
    @serial = @collection.serial
  end

  # combine errors provided in the report with errors we may have detected
  # locally (eg. unresponsiveness)
  def errors
    errors = []
    unless @local_error.nil?
      errors << @local_error
    end
    unless @latest.nil? or @latest[:errors].nil?
      errors.concat(@latest[:errors])
    end
    errors
  end

  def state
    if !@local_error.nil?
      return :failed
    elsif !@latest.nil? and !@latest[:state].nil?
      return @latest[:state].to_sym
    end
    if !@latest.nil? and @latest[:state].nil?
      puts "state is nil: "+@latest.inspect
    end
    return :unknown
  end

  # difference between global serial and this hosts
  def update_tick_delta
    @collection.serial - @serial
  end

  # number of seconds since last update
  def update_time_delta
    @update_time - Time.now.to_i
  end

  # use the two methods above to guess if this host has become unresponsive.
  def is_unresponsive?
    return (update_tick_delta >= @ticks_before_unresponsive and update_time_delta >= @time_before_unresponsive)
  end

  # use this method to mark this node as failed, with the reason set into
  # @local_error. then notify the collection.
  def mark_failed(failmsg)
    @local_error = failmsg
    @collection.run_notify(state, self)
  end

  # called just before we call the run action. used to figure out how long
  # the agent has been running its background process (hopefully).
  def start
    @run_time = Time.now.to_i
  end

  # errors in the report if we have a report, or an empty array
  # (we can't see any yet)
  def report_errors
    if !@latest.nil? and !@latest[:report_errors].nil?
      return @latest[:report_errors]
    else
      return []
    end
  end

  # print the errors in the report prefixed by a + symbol. these are
  # read from last_run_report.yaml and are probably what you would see on a
  # console running puppet. And print errors detected by our agent prefixed
  # with a minus.
  def print_failures
    report_errors.each { | err| puts "     + #{err}" }
    errors.each { |err| puts "     - #{err}" }
  end
end

end # PuppetNG Module
end # Util Module
end # MCollective Module

class MCollective::Application::Puppetng<MCollective::Application
  description "puppet runner"

  include MCollective::Util::PuppetNG

  usage <<-END_OF_USAGE
mco puppetng [OPTIONS] [FILTERS] <ACTION>
Usage: mco puppetng run [--concurrency CONCURRENCY] [--runid RUNID] [--noop]

The ACTION can be one of the following:

run - invoke a puppet run on matching nodes
check_run - get status back from nodes.

Options:

--concurrency <number> - Only run Puppet on <number> hosts in parallel (defaults to all)
--runid <runid>        - Use this run ID instead of generating one automatically
--noop                 - Do a noop run
--tags                 - Tags to pass to the puppet agent

For FILTERS help, see ????
  END_OF_USAGE

  option :runid,
    :arguments => ["--runid RUNID"],
    :description => "Run ID to use",
    :type => String

  option :concurrency,
    :arguments => ["--concurrency CONCURRENCY"],
    :description => "Run on a maximum of this many hosts in parallel (defaults to all)",
    :type => Integer

  option :nocolor,
    :arguments => ["--nocolor"],
    :description => "don't color output",
    :type        => :bool

  option :noop,
    :arguments => ["--noop"],
    :description => "noop run",
    :type        => :bool,
    :default     => false

  option :tags,
    :arguments => ["--tags TAGS"],
    :description => "tags to pass to the puppet agent",
    :type        => :String

  def post_option_parser(configuration)
    if ARGV.length >= 1
      configuration[:command] = ARGV.shift

      unless ["run","check_run"].include?(configuration[:command])
        raise "Action not found."
      end
    else
      raise "Please specify a command"
    end
  end

  def validate_configuration(configuration)
    if configuration.include?(:nocolor)
      $colorize = false
    else
      $colorize = true
    end

    @observers.each { |o| o.validate_configuration(configuration) if o.respond_to?(:validate_configuration) }
  end

  def initialize
    @observers = []

    @config = MCollective::Config.instance
    observer_require = @config.pluginconf.fetch("puppetng.observer_require", nil)
    observer_class = @config.pluginconf.fetch("puppetng.observer_class", nil)

    require observer_require unless observer_require.nil?
    unless observer_class.nil?
      klass = observer_class.split("::").inject(Object) {|base, str| base.const_get(str)}
      @observers << klass.new
    end
  end

  # actions are mapped to <commandname>_command
  def main
    impl_method = "%s_command" % configuration[:command]

    if respond_to?(impl_method)
      send(impl_method)
    else
      raise "Do not know how to handle the '%s' command" % configuration[:command]
    end
  end

  # record when we last prinetd hosts in progress
  # and display in progress hosts, truncating if necessary to keep output tidy.
  def print_running(hosts)
    @last_running_display = Time.now.to_i
    r = hosts.local_running
    preview_hosts = r.map { |h| h.hostname }
    if r.length > @config.pluginconf.fetch("puppetng.display_progress_hosts_max", DISPLAY_PROGRESS_MAX_HOSTS).to_i
      preview_hosts = preview_hosts.slice(0, @config.pluginconf.fetch("puppetng.display_progress_hosts_preview", DISPLAY_PROGRESS_HOSTS_PREVIEW).to_i)
      puts "#{logtime} in progress: #{preview_hosts.join(", ")} and #{r.length - preview_hosts.length} other hosts."
    else
      puts "#{logtime} in progress: #{preview_hosts.join(", ")}"
    end
  end

  def get_runid
    if configuration[:runid]
      return configuration[:runid]
    else
      # use the uuidgen utility to create a UUID.
      begin
        return `uuidgen`.chomp
      # it probably isn't on this system, use a timestamp instead.
      rescue
        return Time.now.strftime("%d%m%y%H%M%S%L")
      end
    end
  end

  def check_run_command
    runid = configuration[:runid]

    if runid.nil?
      puts "No run ID"
      exit 1
    end

    mc = rpcclient("puppetng")
#    mc.progress = false

    targets = mc.discover

    if targets.length < 1
      puts "no targets discovered."
      exit 1
    end

    results = mc.check_run(:runid => runid)

    results.sort { |a,b| a[:sender] <=> b[:sender] }.each do |response|
      senderid = response[:sender]
      data = response.results[:data]

      state = data[:state]
      state = state.green if state == "success"
      state = state.red if state == "failed"
      state = state.yellow if state == "running"
      
      puts "#{senderid} .. #{state}"
    end

    puts "" if results.length > 0
    printrpcstats :summarize => true
  end

  def txn_start(serial)
    @observers.each { |o| o.on_txn_start(serial) if o.respond_to?(:on_txn_start) }
  end

  def txn_end(serial)
    @observers.each { |o| o.on_txn_end(serial) if o.respond_to?(:on_txn_end) }
  end

  # the main 'run' command.
  def run_command
    # the run ID can be provided (could be useful if another system kicks
    # off the run and wants to use the output).

    runid = get_runid
    mc = rpcclient("puppetng")
    mc.progress = false

    targets = mc.discover

    puts "#{logtime} discovered #{targets.length} hosts"
    puts "report ID: #{runid}"
    puts ""

    # check we aren't going to overload our puppetmaster with too many concurrent runs.
    # provide --concurrency explictly if you're not sure.
    exit_if_exceed_concurrency = @config.pluginconf.fetch("puppetng.exit_if_exceed_concurrency", -1).to_i
    if exit_if_exceed_concurrency > 0 and targets.length > exit_if_exceed_concurrency and configuration[:concurrency].nil?
      puts "#{targets.length} targets were discovered but no --concurrency setting was provided. refusing to run, as you should probably consider setting one."
      exit 1
    end

    time_before_unresponsive = @config.pluginconf.fetch("puppetng.time_before_unresponsive", TIME_BEFORE_UNRESPONSIVE)
    ticks_before_unresponsive = @config.pluginconf.fetch("puppetng.ticks_before_unresponsive", TICKS_BEFORE_UNRESPONSIVE)
    # initialize the HostCollection with McoHost instances.
    hosts = HostCollection.new(mc, runid)
    hosts.observers = @observers
    targets.each do |target|
      host = hosts[target] = McoHost.new(target, hosts)
      host.ticks_before_unresponsive = ticks_before_unresponsive
      host.time_before_unresponsive = time_before_unresponsive
      puts "  * #{host.hostname}"
    end
    
    filters = mc.filter
    @observers.each { |o| o.discovery(hosts, filters) if o.respond_to?(:discovery) }

    puts ""

    @last_running_display = Time.now.to_i

    while hosts.has_incomplete?
      hosts.serial += 1

      # shuffling the hostnames can give a more evenly distributed
      # load on the puppetmaster if your hosts are classified by hostname.
      pending = hosts.pending.shuffle

      # if concurrency is provided, pop hosts off the pending list until the number
      # running + would run fits within concurrency.
      unless configuration[:concurrency].nil?
        while hosts.local_running.length + pending.length > configuration[:concurrency]
          pending.pop
        end
      end

      # tell the user we're starting a run, and record that in the McoHost.
      pending.each do |host|
        puts "#{logtime} #{host.hostname} start.".blue
        host.start
      end

      # we have runs to kick off
      
      txn_start(hosts.serial)
      if pending.length > 0
        mc.discover(:nodes => pending.map { |host| host.hostname })
        opts = { :runid => runid, :noop => configuration[:noop] }
        opts[:tags] = configuration[:tags] unless configuration[:tags].nil?
        runs = mc.run(opts)
        runs.each do |s|
          senderid = s[:sender]
          hostobj = hosts[senderid]
          hostobj.run_init(s)
        end

        pending.each { |host| host.check_run_failed }
      end
      txn_end(hosts.serial)

      hosts.serial += 1

      # we have incomplete hosts which need their runs checking on.
      txn_start(hosts.serial)
      if hosts.has_incomplete?
        mc.discover(:nodes => hosts.local_running_hostnames)
        mc.check_run(:runid => runid).each do |s|
          senderid = s[:sender]
          # get McoHost instance using hostname from reply as key
          hostobj = hosts[senderid]
          # update it with the response
          hostobj.update(s)
        end

        hosts.check_for_unresponsive

        if Time.now.to_i - @last_running_display > @config.pluginconf.fetch("puppetng.display_progress_interval", 90).to_i
          print_running(hosts)
        end
	txn_end(hosts.serial)
      else
        # we're done
	txn_end(hosts.serial)
        break
      end

      sleep 1
    end

    # print a summary of failed hosts if there are any
    failures = hosts.failed
    if failures.length > 0
      puts ""
      puts "The following hosts failed:"
      failures.each do |host|
        puts " * #{host.hostname}".red
        host.print_failures
      end
    end

    # print a summary at the end
    puts "\n" + hosts.get_summary

    @observers.each { |o| o.on_complete(hosts, failures) if o.respond_to?(:on_complete) }
  end
end
