require 'stackbuilder/support/namespace'
require 'stackbuilder/support/mcollective'

class Support::MCollectiveHostcleanup
  include Support::MCollective

  def hostcleanup(fqdn, action)
    mco_client('hostcleanup') do |hostcleanup_mc|
      hostcleanup_mc.progress = false
      hostcleanup_mc.reset_filter
      case action
      when 'puppet'
        hostcleanup_mc.class_filter('role::puppetserver')
        hostcleanup_mc.fact_filter 'logicalenv', '/(oy|pg|lon|st)/'
      when 'mongodb'
        hostcleanup_mc.class_filter('role::mcollective_registrationdb')
        hostcleanup_mc.fact_filter 'logicalenv', '/(oy|pg|lon|st)/'
      when 'nagios'
        hostcleanup_mc.class_filter('nagios')
        hostcleanup_mc.fact_filter 'domain', '/(oy|pg|lon)/'
      end
      output_result hostcleanup_mc.send(action, :fqdn => fqdn)
    end
  end

  private

  def status_code(status)
    return 'OK' if status
    'ERROR'
  end

  def output_result(responses)
    responses.each do |resp|
      if resp.results[:statuscode] == 0
        printf(" %-48s: %s - %s, output: %s\n", resp.results[:sender], \
               resp.action, \
               status_code(resp.results[:data][:statuscode]), \
               resp.results[:data][:status])
      else
        printf(" %-48s: %s - ERROR %s\n", resp.results[:sender], resp.action, resp.results[:statusmsg])
      end
    end
  end
end
