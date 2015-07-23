require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::CiSlave < Stacks::MachineDef
  attr_accessor :mysql_version

  def initialize(server_group, index)
    super(server_group.name + "-" + index, [:mgmt])
    @mysql_version = '5.1.49-1ubuntu8'
    self
  end

  def availability_group
    nil
  end

  def bind_to(environment)
    super(environment)
  end

  def to_enc
    enc = super()
    enc.merge!('role::cinode_precise' => {
                 'mysql_version' => @mysql_version
               })
    enc
  end
end
