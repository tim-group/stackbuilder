module Support
end

module Support::MCollectivePuppet
  include Support::MCollective

  def ca_sign(machines_fqdns, &block)
    timeout = 60
    callback = Support::Callback.new(&block)
    needs_signing = machines_fqdns.clone.to_set

    start_time = now
    while not needs_signing.empty? and not timed_out(start_time, timeout)
      all_requests = puppetca() do |mco|
        mco.list.map do |response|
          response[:data][:requests]
        end
      end.flatten.to_set

      ready_to_sign = all_requests.intersection(needs_signing)

      ready_to_sign.each do |machine_fqdn|
        signed = puppetca() do |mco|
          mco.sign(:certname => machine_fqdn).select do |response|
            response[:statuscode] == 0
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
    return data !=nil &&
    data.has_key?(:resources) &&
    data[:resources] !=nil &&
    data[:resources]["failed"] == 0 &&
    data[:resources]["failed_to_restart"] == 0? "passed" : "failed"
  end

  ## todo refactor this - tis aweful
  def wait_for_complete(machine_fqdns, &block)
    timeout = 900
    callback = Support::Callback.new(&block)
    unknown_machines = machine_fqdns.clone.to_set
    machines_that_failed_puppet = {}
    all_stopped = false
    start_time = now

    while not unknown_machines.empty? and not timed_out(start_time, timeout)
      current_status = Hash[puppetd(machine_fqdns.sort) do |mco|
        mco.status(:timeout => 30).map do |response|
          [response[:sender], response[:data][:status]]
        end
      end]

      completed_machines = Hash[current_status.select do |machine, status|
        status == "stopped"
      end].keys.to_set

      if (completed_machines.size >0)
        unknown_machines -= completed_machines

        last_run_summary = Hash[puppetd(completed_machines.to_a.sort) do |mco|
          mco.last_run_summary(:timeout => 30).map do |response|
            [response[:sender], puppet_run_passed?(response[:data])]
          end
        end]

        last_run_summary_results = last_run_summary.merge Hash[unknown_machines.map do |machine|
          [machine, "unaccounted_for"]
        end]

        failed = last_run_summary.reject do |machine, result|
          result == "passed"
        end
        machines_that_failed_puppet.merge!(failed)
      end
    end

    raise "some machines failed puppet runs: #{machines_that_failed_puppet.keys.sort.join(', ')}" if machines_that_failed_puppet.size>0
    raise "some machines puppet runs were unaccounted for after #{now - start_time} sec" if unknown_machines.size>0
  end

  def ca_clean(machines_fqdns, &block)
    callback = Support::Callback.new(&block)
    machines_fqdns.each do |machine_fqdn|
      puppetca() do |mco|
        cleaned = mco.clean(:certname => machine_fqdn).select do |response|
          response[:statuscode] == 0
        end.size > 0
        if cleaned
          callback.invoke :success, machine_fqdn
        else
          callback.invoke :failed, machine_fqdn
        end
      end
    end
  end

  def puppetca(&block)
    mco_client("puppetca", &block)
  end

  def puppetd(nodes, &block)
    mco_client("puppetd", :nodes => nodes, &block)
  end

  def timed_out(start_time, timeout)
    return (now - start_time) > timeout
  end

  # factor out the clock so it's mockable in tests
  def now
    return Time.now
  end

end
