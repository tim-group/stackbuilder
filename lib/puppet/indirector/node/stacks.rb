# XXX mmazurek 2015-07-31 this is replaced by bin/stacks_indirector and can go away after puppet.conf has
# been reconfigured to use bin/stacks_indirector.

$LOAD_PATH << '/usr/local/lib/site_ruby/timgroup/'
require 'stackbuilder/stacks/environment'
require 'stackbuilder/stacks/inventory'
$LOAD_PATH.delete('/usr/local/lib/site_ruby/timgroup/')
require 'puppet/node'
require 'puppet/indirector/node/plain'
require 'yaml'
require 'fileutils'
require 'logger'

class Puppet::Node::Stacks < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def initialize(
    stacks_inventory = Stacks::Inventory.from_dir('/etc/stacks'),
    delegate = Puppet::Node::Plain.new,
    dump_enc = true,
    dump_enc_dir = '/var/log/stacks/enc',
    dump_enc_log = '/var/log/stacks/enc.log'
  )
    @stacks_inventory = stacks_inventory
    @delegate = delegate
    @dump_enc = dump_enc
    @dump_enc_dir = dump_enc_dir
    @dump_enc_logfile = dump_enc_dir
    @logger = Logger.new('/dev/null')
    @logger.progname = 'stacks_indirector'

    return unless @dump_enc
    FileUtils.mkdir_p @dump_enc_dir unless File.exist?(@dump_enc_dir)
    @logger = Logger.new(dump_enc_log, 'daily')
  end

  def find(request)
    start_time = Time.now
    node = @delegate.find(request)
    machine = @stacks_inventory.find(request.key)
    if machine
      classes = machine.to_enc
      if @dump_enc
        File.open("#{@dump_enc_dir}/#{request.key}.yaml", 'w') { |file| file.write(classes.to_yaml) }
      end
      node.classes = classes if classes
      node.parameters['logicalenv'] = machine.environment.name
      node.parameters['stackname'] = machine.stackname if machine.respond_to?(:stackname)
    end

    duration = "#{((Time.now - start_time) * 1000)}ms"
    if machine
      @logger.info("Node found: #{request.key}, classes: #{classes.size}, duration: #{duration}")
    else
      @logger.info("Node not found: #{request.key}, duration: #{duration}")
    end

    node
  end
end
