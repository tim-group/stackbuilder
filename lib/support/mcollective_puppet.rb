module Support
end

module Support::MCollectivePuppet
  include Support::MCollective

  def timed_out(start_time, timeout)
    return (Time.now() - start_time) > timeout
  end

  def ca_sign(machines_fqdns, &block)
    timeout = 60
    callback = Support::Callback.new
    callback.instance_eval(&block)
    needs_signing = machines_fqdns.clone.to_set

    start_time = Time.new
    while not needs_signing.empty? and not timed_out(start_time, timeout)
      all_requests = mco_client("puppetca") do |mco|
        mco.list.map do |response|
          response[:data][:requests]
        end
      end.flatten.to_set

      ready_to_sign = all_requests.intersection(needs_signing)

      ready_to_sign.each do |machine_fqdn|
        signed = mco_client("puppetca") do |mco|
          mco.sign(:certname => machine_fqdn).select do |response|
            response[:statuscode]==0
          end.size > 0
        end
        if signed
          callback.invoke :success, machine_fqdn
        else
          callback.invoke :failed, machine_fqdn
        end
        needs_signing.delete(machine_fqdn)
      end
    end

    needs_signing.each do |machine_fqdn|
      callback.invoke :unaccounted, machine_fqdn
    end
  end


  def puppet_run_passed?(data)
    return data[:resources]["failed"]==0 && data[:resources]["failed_to_restart"]==0? "passed" : "failed"
  end

  def wait_for_complete(machine_fqdns, &block)
    timeout = 5
    callback = Support::Callback.new
    callback.instance_eval(&block)

    unknown_machines = machine_fqdns.clone.to_set
    all_stopped = false
    start_time = Time.new

    while not unknown_machines.empty? and not timed_out(start_time, timeout)
      current_status = Hash[mco_client("puppetd", :nodes=> machine_fqdns) do |mco|
        mco.status(:timeout=>30).map do |response|
          [response[:sender], response[:data][:status]]
        end
      end]

      completed_machines = Hash[current_status.select do |machine, status|
        status=="stopped"
      end].keys.to_set

      unknown_machines -= completed_machines

      last_run_summary = Hash[mco_client("puppetd", :nodes=> completed_machines.to_a) do |mco|
        mco.last_run_summary(:timeout=>30).map do |response|
          [response[:sender], puppet_run_passed?(response[:data])]
        end
      end]

      last_run_summary = last_run_summary.merge Hash[unknown_machines.map do |machine|
        [machine, "unaccounted_for"]
      end]

      machines_that_failed_puppet = last_run_summary.reject do |machine, result|
        result == "passed"
      end

      pp last_run_summary

      raise "some machines failed puppet runs " if machines_that_failed_puppet.size>0
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
