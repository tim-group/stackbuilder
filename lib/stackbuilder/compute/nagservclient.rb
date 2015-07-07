require 'stackbuilder/compute/namespace'
require 'mcollective'
require 'stackbuilder/support/mcollective'

class Compute::NagsrvClient
  include Support::MCollective

  def toggle_notify(action, mgmt_fqdn)
    mco_client("nagsrv") do |mco|
      mco.send(action.to_sym, :forhost => mgmt_fqdn).map do |node|
        {
          :sender => node.results[:sender],
          :statuscode => node[:statuscode],
          :result => node.results[:data][:output].size
        }
      end
    end
  end
end
