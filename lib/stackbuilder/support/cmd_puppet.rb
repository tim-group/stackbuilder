require 'stackbuilder/support/mcollective_puppet'

module CMDPuppet
  private

  include Support::MCollectivePuppet

  def puppet_clean(machine_def)
    puppet_certs_to_clean = []
    machine_def.accept do |child_machine_def|
      if child_machine_def.respond_to?(:mgmt_fqdn)
        if child_machine_def.needs_signing?
          puppet_certs_to_clean << child_machine_def.mgmt_fqdn
        else
          logger(Logger::INFO) { "removal of cert not needed for #{child_machine_def.mgmt_fqdn}" }
        end
      end
    end

    ca_clean(puppet_certs_to_clean) do
      on :success do |machine|
        logger(Logger::INFO) { "successfully removed cert for #{machine}" }
      end
      on :failed do |machine|
        logger(Logger::WARN) { "failed to remove cert for #{machine}" }
      end
    end
  end
end
