require 'stackbuilder/stacks/environment'
require 'stackbuilder/stacks/inventory'
require 'puppet/node'
require 'puppet/indirector/node/plain'
require 'yaml'
require 'fileutils'

class Puppet::Node::Stacks < Puppet::Indirector::Plain
  desc "generates the necessary wiring for all nodes in a stack."

  def initialize(
    stacks_inventory = Stacks::Inventory.new('/etc/stacks'),
    delegate = Puppet::Node::Plain.new,
    dump_enc = true,
    dump_enc_dir = '/var/log/stacks/enc'
  )
    @stacks_inventory = stacks_inventory
    @delegate = delegate
    @dump_enc = dump_enc
    @dump_enc_dir = dump_enc_dir
  end

  def find(request)
    node = @delegate.find(request)
    machine = @stacks_inventory.find(request.key)
    if machine
      classes = machine.to_enc
      if @dump_enc
        FileUtils.mkdir_p @dump_enc_dir unless File.exist?(@dump_enc_dir)
        File.open("#{@dump_enc_dir}/#{request.key}.yaml", 'w') { |file| file.write(classes.to_yaml) }
      end
      node.classes = classes if classes
      node.parameters['logicalenv'] = machine.environment.name
    end
    node
  end
end
