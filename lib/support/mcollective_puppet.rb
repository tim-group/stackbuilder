module Support
end

class Hash
  def hash_select(&block)
    return Hash[select(&block)]
  end
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

    callback.finish
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
    callback.finish
  end

  def wait_for_complete(machine_fqdns, timeout=900)
    start_time = now

    fates = Hash[machine_fqdns.map { |fqdn| [fqdn, "unaccounted for"] }]
    while not (undecided = fates.hash_select { |k, v| v != "passed" && v != "failed" }).empty? and not timed_out(start_time, timeout)
      undecided_statuses = puppetd_status(undecided.keys)
      fates.merge!(undecided_statuses)
      stopped_statuses = undecided_statuses.hash_select { |k, v| v == "stopped" }
      stopped_results = puppetd_last_run_summary_processed(stopped_statuses.keys)
      fates.merge!(stopped_results)
    end

    unsuccessful = fates.hash_select { |k, v| v != "passed" }
    raise "some machines did not successfully complete puppet runs within #{now - start_time} sec: #{unsuccessful.to_a.sort.map { |kv| "#{kv[0]} (#{kv[1]})" }.join(', ')}" unless unsuccessful.empty?
  end

  def puppetd_status(fqdns)
    puppetd_query(:status, fqdns) do |data|
      data[:status]
    end
  end

  def puppetd_last_run_summary_processed(fqdns)
    puppetd_query(:last_run_summary, fqdns) do |data|
      result = result_for_summary(data)
      if result != "passed"
        puts "bad result: #{data.inspect}"
      end
      result
    end
  end

  def result_for_summary(data)
    # the agent returns malformed data in a short window between a run finishing and the state file being updated, so treat that as not yet stopped
    return "stopping" if data.nil?
    resources = data[:resources]
    return "stopping" if resources.nil?
    failed = resources["failed"]
    failed_to_restart = resources["failed_to_restart"]
    return "stopping" if failed.nil? or failed_to_restart.nil?
    return (failed == 0 && failed_to_restart == 0) ? "passed" : "failed"
  end

  def puppetd_query(selector, fqdns, &block)
    return {} if fqdns.empty?
    Hash[puppetd(fqdns.sort) do |mco|
      mco.send(selector, :timeout => 30).map do |response|
        [response[:sender], block.call(response[:data])]
      end
    end]
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
