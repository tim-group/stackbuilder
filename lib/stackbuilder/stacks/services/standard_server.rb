require 'stackbuilder/stacks/namespace'
require 'stackbuilder/stacks/machine_def'

class Stacks::Services::StandardServer < Stacks::MachineDef
  def to_enc
    enc = super
    enc.merge!('server::default_new_mgmt_net_local' => {})
    enc
  end
end
