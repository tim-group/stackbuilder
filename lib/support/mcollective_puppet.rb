module Support
end

module Support::MCollectivePuppet
  include Support::MCollective

  def ca_sign(machines_fqdns, &block)
    callback = Support::Callback.new
    callback.instance_eval(&block)

    machines_fqdns.each do |machine_fqdn|
      mco_client("puppetca") do |mco|
        cleaned = mco.sign(:certname => machine_fqdn).select do |response|
          response[:statuscode]==0
        end.size > 0
        if cleaned
          callback.invoke :success, machine_fqdn
        else
          callback.invoke :failed, machine_fqdn
        end
      end
    end
  end

  def ca_clean(machines_fqdns, &block)
    callback = Support::Callback.new
    callback.instance_eval(&block)
    machines_fqdns.each do |machine_fqdn|
      mco_client("puppetca") do |mco|
        cleaned = mco.clean(:certname => machine_fqdn).select do |response|
          response[:statuscode]==0
        end.size > 0
        if cleaned
          callback.invoke :success, machine_fqdn
        else
          callback.invoke :failed, machine_fqdn
        end
      end
    end
  end
end
