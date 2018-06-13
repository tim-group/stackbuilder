require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

module Support
  class MCollectiveDeployapp
    include Support::MCollective

    def get_application_status(fqdn, spec)
      statuses = mco_client("deployapp", :nodes => [fqdn]) do |mco|
        mco.status(:spec => spec).map do |response|
          fail response[:statusmsg] unless response[:statuscode] == 0
          log_deployapp_response(response)
          fail response[:data] unless response[:data][:successful]
          response[:data][:statuses]
        end
      end.flatten
      fail "could not determine application status: #{statuses}" unless statuses.length == 1
      statuses[0]
    end

    def deploy_app_version(fqdn, spec, version)
      logger(Logger::INFO) { "Deploying app version #{version} on #{fqdn} : #{spec}" }
      mco_client("deployapp", :nodes => [fqdn]) do |mco|
        mco.update_to_version(:spec => spec, :version => version).map do |response|
          fail response[:statusmsg] unless response[:statuscode] == 0
          log_deployapp_response(response)
          fail response[:data] unless response[:data][:successful]
        end
      end
    end

    def enable_participation(fqdn, spec)
      logger(Logger::INFO) { "Enabling participation app on #{fqdn} : #{spec}" }
      mco_client("deployapp", :nodes => [fqdn]) do |mco|
        mco.enable_participation(:spec => spec).map do |response|
          fail response[:statusmsg] unless response[:statuscode] == 0
          log_deployapp_response(response)
          fail response[:data] unless response[:data][:successful]
        end
      end
    end

    private

    def log_deployapp_response(response)
      if response[:data] && response[:data][:logs]
        logs = response[:data][:logs]
        logs[:debugs].each { |msg| logger(Logger::DEBUG) { msg } } if logs[:debugs]
        logs[:infos].each { |msg| logger(Logger::INFO) { msg } } if logs[:infos]
        logs[:warns].each { |msg| logger(Logger::WARN) { msg } } if logs[:warns]
        logs[:errors].each { |msg| logger(Logger::ERROR) { msg } } if logs[:errors]
      else
        logger(Logger::WARN) { "no logs from mco deployapp call" }
      end
    end
  end
end
