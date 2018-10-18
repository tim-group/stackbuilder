require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::StandardServer < Stacks::MachineDef
  def to_enc
    enc = super
    enc.merge!('server' => {})
    enc
  end
end
