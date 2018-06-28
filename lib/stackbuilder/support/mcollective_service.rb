require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveService
  include Support::MCollective

  def stop_service(service_name, fqdns)
    mco_client("service", :timeout => 5, :nodes => fqdns) { |mco| mco.stop(:service => service_name) }
  end
end
