$LOAD_PATH << '/usr/local/lib/site_ruby/timgroup'
require 'orc/util/option_parser' # XXX decouple orc from stackbuiler somehow
$LOAD_PATH.delete('/usr/local/lib/site_ruby/timgroup')
require 'rake'
require 'pp'
require 'yaml'
require 'rubygems'
require 'stackbuilder/stacks/environment'
require 'stackbuilder/stacks/inventory'
require 'stackbuilder/support/cmd'
require 'stackbuilder/support/mcollective'
require 'stackbuilder/support/mcollective_puppet'
require 'stackbuilder/support/nagios'
require 'stackbuilder/support/zamls'

require 'set'
require 'rspec'
require 'stackbuilder/compute/controller'
require 'stackbuilder/stacks/factory'
require 'thread'

# XXX refactor this somehow, causes warnings in new rubys. hide the warnings for now
# rubocop:disable Style/ClassVars
warn_level = $VERBOSE
$VERBOSE = nil
@@factory = @factory = Stacks::Factory.new
$VERBOSE = warn_level
# rubocop:enable Style/ClassVars

include Rake::DSL
include Support::MCollective
extend Stacks::Core::Actions

environment_name = ENV.fetch('env', 'dev')
@environment = @factory.inventory.find_environment(environment_name)
if @environment.nil?
  logger(Logger::ERROR) { "environment \"#{environment_name}\" does not exist" }
  exit 1
end

RSpec::Core::Runner.disable_autorun!

####
# TODO
# general:
#         use logging
#         push stuff back out of here
#         does it complain well when keys aren't to be found anywhere?
#           probably want to have a different key in each dc?
#
# possibly:
#         implement visitor pattern to traverse tree
#
# allocate: tidy up output
#
# launch: tidy up output
#         clearly indicate success or failure to launnch
#         launch in parallel
#
# clean machines:
#         clean needs to show what it actually cleaned, currently dumps results
#         need to account for which host each machine was cleaned from
#
# mping:
#         tidy, test and
#
# puppetclean:
#       warn if cert clean did not occur
#       show positive clean action clearly in log
#
# puppetsign:
#       warn if signing did not occur
#       use output more wisely
#       show positive sign action clearly in log
#
# need workflow tasks to tie builds together.
#   ie provision dependson [launch, mping, puppet, test]
#      clean     dependson [destroy_vms, clean_certs]
#

def sbtask(name, &block)
  task name do |task|
    @start_time = Time.now
    puts "\e[1m\e[34m:#{task}\e[0m"
    begin
      block.call
    rescue StandardError => e
      @elapsed = Time.now - @start_time
      t = sprintf("%.2f", @elapsed)
      puts "\n\e[1m\e[31m:#{task} failed in #{t}\e[0m\n"
      raise e
    end

    @elapsed = Time.now - @start_time
    t = sprintf("%.2f", @elapsed)
    puts "\n\e[1m\e[32m:#{task} passed in #{t}s\e[0m\n"
  end
end

namespace :sbx do
  desc 'Print a report of KVM host CPU/Storage/Memory allocation'
  task :audit_host_machines do
    system("stacks -e #{environment.name} -p . audit")
  end

  desc 'create a yaml file describing the entire infrastructure'
  task :compile do
    system('stacks -p . compile')
  end

  desc 'list describing the internal hierachy in stackbuilder'
  task :ls do
    system("stacks -e #{environment.name} -p . ls")
  end

  def rake_task_name(machine_def)
    if machine_def.respond_to?(:identity)
      machine_def.identity
    else
      fail "#{machine_def} does not respond to identity. Unknown type detected"
    end
  end

  def indent(text, n, char)
    n.times do
      text = char + text.to_s
    end
    text
  end

  def show_tree
    puts 'top'
    @environment.accept do |machine_def|
      puts "#{rake_task_name(machine_def)} (#{machine_def.class} -> #{machine_def.type_of?})"
    end
  end

  cmd = CMD.new
  require 'set'
  machine_names = Set.new
  rake_task_names = Set.new
  @environment.accept do |machine_def|
    rake_task_name = rake_task_name(machine_def)

    if rake_task_names.include?(rake_task_name)
      fail "Duplicate rake task detected: #{rake_task_name} in #{machine_def.environment.name}. " \
           "Look for a stack that has the same name as the server being created.\neg.\n" \
           " stack '#{rake_task_name}' do\n  app '#{rake_task_name}'"
    end
    rake_task_names << rake_task_name

    namespace rake_task_name do
      RSpec::Core::Runner.disable_autorun! # XXX wtf does this do
      if machine_names.include?(rake_task_name)
        fail "Duplicate machine name detected: #{machine_def.name} in #{machine_def.environment.name}. " \
          "Look for a stack that has the same name as the server being created.\neg.\n" \
          " stack '#{machine_def.name}' do\n  app '#{machine_def.name}'"
      end
      machine_names << "#{machine_def.environment.name}:#{machine_def.name}"

      desc "outputs the specs for these machines, in the format to feed to the provisioning tools"
      task :to_specs do
        puts ZAMLS.to_zamls(machine_def.to_specs)
      end

      # FIXME : Take this terrible, un-testable code out of rake
      desc "outputs the vip spec for these machines in a human readable format (dns allocation consumes the hash)"
      task :to_vip_spec do
        puts ZAMLS.to_zamls(machine_def.to_vip_spec(:primary_site))
        puts ZAMLS.to_zamls(machine_def.to_vip_spec(:secondary_site)) unless machine_def.enable_secondary_site
      end

      if machine_def.respond_to? :to_enc
        desc "External Node Classifiers; fed to puppet"
        task :to_enc do
          puts ZAMLS.to_zamls(machine_def.to_enc)
        end
      end

      task :prepare_dependencies => if ENV.fetch('SKIP_PREPARE_DEPENDENCIES', 'false') == 'true'
                                      ['notify_prepare_dependencies_disabled']
                                    else
                                      ['allocate_vips', 'allocate_ips', 'puppet:prepare_dependencies']
                                    end

      task :notify_prepare_dependencies_disabled do
        logger(Logger::WARN) { 'skipping prepare_dependencies as --skip-prepare-dependencies flag is set' }
      end

      task :provision_machine do
        cmd.do_provision_machine(@factory.services, machine_def)
      end

      desc "perform all steps required to create and configure the machine(s)"
      task :provision => %w(prepare_dependencies provision_machine nagios:refresh)

      desc "perform a clean followed by a provision"
      task :reprovision => %w(clean provision_machine)

      desc "allocate these machines to hosts (but don't actually launch them - this is a dry run)"
      sbtask :allocate do
        cmd.do_allocate(@factory.services, machine_def)
      end

      desc "launch these machines"
      sbtask :launch do
        cmd.do_launch(@factory.services, machine_def)
      end

      desc "resolve the IP numbers of these machines"
      sbtask :resolve do
        computecontroller = Compute::Controller.new
        pp computecontroller.resolve(machine_def.to_specs)
      end

      desc "disable notify for these machines"
      sbtask :disable_notify do
        computecontroller = Compute::Controller.new
        computecontroller.disable_notify(machine_def.to_specs)
      end

      desc "enable notify for these machines"
      sbtask :enable_notify do
        computecontroller = Compute::Controller.new
        computecontroller.enable_notify(machine_def.to_specs)
      end

      desc "allocate IPs for these machines"
      sbtask :allocate_ips do
        cmd.do_allocate_ips(@factory.services, machine_def)
      end

      # FIXME : Take this terrible, un-testable code out of rake
      desc "allocate VIPs for these virtual services"
      sbtask :allocate_vips do
        vips = []
        machine_def.accept do |child_machine_def|
          if child_machine_def.respond_to?(:to_vip_spec)
            vips << child_machine_def.to_vip_spec(:primary_site)
            vips << child_machine_def.to_vip_spec(:secondary_site) if child_machine_def.enable_secondary_site
          end
        end
        if vips.empty?
          logger(Logger::INFO) { 'no vips to allocate' }
        else
          @factory.services.dns.allocate(vips)
        end
      end

      desc "allocate cnames"
      sbtask :allocate_cnames do
        all_specs = machine_def.flatten.map(&:to_spec)
        require 'pp'
        pp all_specs
        @factory.services.dns.do_cnames('add', all_specs)
      end

      # FIXME : Take this terrible, un-testable code out of rake
      desc "free IPs for these virtual services"
      sbtask :free_vips do
        vips = []
        machine_def.accept do |child_machine_def|
          if child_machine_def.respond_to?(:to_vip_spec)
            vips << child_machine_def.to_vip_spec(:primary_site)
            vips << child_machine_def.to_vip_spec(:secondary_site) if child_machine_def.enable_secondary_site
          end
        end
        @factory.services.dns.free(vips)
      end

      desc "free IPs"
      sbtask :free_ips do
        all_specs = machine_def.flatten.map(&:to_spec)
        @factory.services.dns.free(all_specs)
      end

      desc "perform an MCollective ping against these machines"
      sbtask :mping do
        hosts = []
        machine_def.accept do |child_machine_def|
          if child_machine_def.respond_to?(:mgmt_fqdn)
            hosts << child_machine_def.mgmt_fqdn
          end
        end
        found = false
        50.times do
          found = mco_client("rpcutil") do |mco|
            hosts.to_set.subset?(mco.discover.to_set)
          end

          sleep 1
          break if found
        end

        fail("nodes #{hosts.join(' ')} not checked in to mcollective") unless found
        logger(Logger::INFO) { "all nodes found in mcollective #{hosts.size}" }
      end

      namespace :puppet do
        desc "run puppet on all of a stack's dependencies"
        sbtask :prepare_dependencies do
          all_dependencies = Set.new
          machine_def.accept do |m|
            all_dependencies += m.dependencies.flatten if m.is_a? Stacks::MachineDef
          end

          dependency_fqdns = []
          all_dependencies.map do |dependency|
            dependency.accept do |m|
              dependency_fqdns << m.mgmt_fqdn if m.is_a? Stacks::MachineDef
            end
          end

          dependency_fqdns = dependency_fqdns.sort.uniq

          require 'tempfile'
          Tempfile.open("mco_prepdeps") do |f|
            f.puts dependency_fqdns.join("\n")
            f.flush

            system('mco', 'puppetng', 'run', '--concurrency', '5', '--nodes', f.path)
          end
        end
      end

      desc 'unallocate machines'
      sbtask :clean do
        cmd.do_clean(machine_def)
      end

      desc 'clean away all traces of these machines'
      sbtask :clean_traces do
        cmd.do_clean_traces(machine_def)
      end

      desc "frees up ip and vip allocation of these machines"
      task :free_ip_allocation => %w(free_ips free_vips)

      namespace :nagios do
        sbtask :refresh do
          hosts = []
          machine_def.accept do |child_machine_def|
            if child_machine_def.respond_to?(:mgmt_fqdn)
              hosts << child_machine_def
            end
          end

          sites = hosts.map(&:fabric).uniq
          nagios_helper = Support::Nagios::Service.new
          nagios_server_fqdns = sites.map { |s| nagios_helper.nagios_server_fqdns_for(s) }.reject(&:nil?).flatten

          if nagios_server_fqdns.empty?
            logger(Logger::WARN) { "skipping #{machine_def.identity} - No nagios servers found in #{sites}" }
          else
            logger(Logger::INFO) { "running puppet on nagios servers (#{nagios_server_fqdns}) so they will discover this node and include in monitoring" }

            require 'tempfile'
            Tempfile.open('mco_puppet_on_nagios') do |f|
              f.puts nagios_server_fqdns.join("\n")
              f.flush

              system('mco', 'puppetng', 'run', '--concurrency', '5', '--nodes', f.path)
            end
          end
        end
      end

      sbtask :showvnc do
        hosts = []
        machine_def.accept do |child|
          hosts << child.name if child.is_a? Stacks::MachineDef
        end
        mco_client("libvirt") do |mco|
          mco.fact_filter "domain=/(st|ci)/"
          results = {}
          hosts.each do |host|
            mco.domainxml(:domain => host) do |result|
              xml = result[:body][:data][:xml]
              sender = result[:senderid]
              unless xml.nil?
                matches = /type='vnc' port='(\-?\d+)'/.match(xml)
                fail "Pattern match for vnc port was nil for #{host}\n XML output:\n#{xml}" if matches.nil?
                fail "Pattern match for vnc port contains no captures for #{host}\n XML output:\n#{xml}" \
                  if matches.captures.empty?
                results[host] = {
                  :host => sender,
                  :port => matches.captures.first
                }
              end
            end
          end
          results.each do |vm, location|
            puts "#{vm}  -> #{location[:host]}:#{location[:port]}"
          end
        end
      end

      desc "carry out all appropriate tests on these machines"
      sbtask :test do
        machine_def.accept do |child_machine_def|
          specpath = File.dirname(__FILE__) + "/../stacktests/#{child_machine_def.clazz}/*.rb"
          describe "#{child_machine_def.clazz}.#{child_machine_def.name}" do
            Dir[specpath].each do |file|
              require file
              test = File.basename(file, '.rb')
              it_behaves_like test, child_machine_def
            end
          end
        end
        result = RSpec::Core::Runner.run([], $stderr, $stdout)

        if (result != 0)
          logger(Logger::ERROR) do
            "The 'test' task failed, indicating the stack is not functioning correctly. " \
              "See the above test output for details."
          end
          abort
        end
      end
    end
  end
end
