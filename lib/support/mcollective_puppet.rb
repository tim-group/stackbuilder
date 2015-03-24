require 'support/namespace'

class Hash
  def hash_select(&block)
    Hash[select(&block)]
  end
end

module Support::MCollectivePuppet
  include Support::MCollective

  def ca_sign(machines_fqdns, &block)
    timeout = 360
    callback = Support::Callback.new(&block)
    needs_signing = machines_fqdns.clone.to_set

    start_time = now
    while !needs_signing.empty? && !timed_out(start_time, timeout)
      all_requests = puppetca do |mco|
        mco.list.map do |response|
          response[:data][:requests]
        end
      end.flatten.to_set

      ready_to_sign = all_requests.intersection(needs_signing)

      ready_to_sign.each do |machine_fqdn|
        signed = puppetca do |mco|
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
      puppetca(machine_fqdn) do |mco|
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

  def wait_for_complete(machine_fqdns, timeout = 3600, &block)
    start_time = now
    callback = Support::Callback.new(&block)

    fates = Hash[machine_fqdns.map { |fqdn| [fqdn, "unaccounted for"] }]
    while !(undecided = fates.hash_select { |k, v| v != "passed" && v != "failed" }).empty? && !timed_out(start_time, timeout)
      old_fates = fates.clone
      undecided_statuses = puppetd_status(undecided.keys)
      fates.merge!(undecided_statuses)
      stopped_statuses = undecided_statuses.hash_select { |k, v| v == "stopped" }
      stopped_results = puppetd_last_run_summary_processed(stopped_statuses.keys)
      stopped_results.sort.each do |machine_fqdn, result|
        if result == "passed"
          callback.invoke(:passed, machine_fqdn)
        elsif result == "failed"
          callback.invoke(:failed, machine_fqdn)
        end
      end
      fates.merge!(stopped_results)
      old_fates.each do |machine_fqdn, old_fate|
        new_fate = fates[machine_fqdn]
        if new_fate != old_fate
          callback.invoke(:transitioned, [machine_fqdn, old_fate, new_fate])
        end
      end
    end

    undecided = fates.hash_select { |k, v| v != "passed" && v != "failed" }
    undecided.sort.each do |machine_fqdn, result|
      callback.invoke(:timed_out, [machine_fqdn, result])
    end

    callback.finish
  end

  def puppetd_status(fqdns)
    puppetd_query(:status, fqdns) do |data|
      data[:status]
    end
  end

  def puppetd_last_run_summary_processed(fqdns)
    puppetd_query(:last_run_summary, fqdns) do |data|
      result_for_summary(data)
    end
  end

  def result_for_summary(data)
    # the agent returns malformed data in a short window between a run finishing and the state file being updated, so treat that as not yet stopped
    return "stopping" if data.nil?
    return "stopping" if data[:summary].nil?
    resources = data[:summary]["resources"]
    return "stopping" if resources.nil?
    failed = resources["failed"]
    failed_to_restart = resources["failed_to_restart"]
    return "stopping" if failed.nil? || failed_to_restart.nil?
    (failed == 0 && failed_to_restart == 0) ? "passed" : "failed"
  end

  def puppetd_query(selector, fqdns, &block)
    return {} if fqdns.empty?
    Hash[puppetd(fqdns.sort) do |mco|
      mco.send(selector, :timeout => 30).map do |response|
        [response[:sender], block.call(response[:data])]
      end
    end]
  end

  def puppetca(machine_fqdn = nil, &block)
    puppetmaster = case machine_fqdn
                   when /\.mgmt\.st\.net\.local$/ then "st-puppetmaster-001.mgmt.st.net.local"
                   when /\.mgmt\.oy\.net\.local$/ then "antarctica.oyldn.youdevise.com"
                   when /\.mgmt\.pg\.net\.local$/ then "australia.pgldn.youdevise.com"
                   when /\.mgmt\.ci\.net\.local$/ then "ldn-puppet-001.youdevise.com"
    end

    if puppetmaster.nil?
      mco_client("puppetca", &block)
    else
      mco_client("puppetca", :nodes => [puppetmaster], &block)
    end
  end

  def puppetd(nodes, &block)
    mco_client("puppet", :nodes => nodes, &block)
  end

  def timed_out(start_time, timeout)
    (now - start_time) > timeout
  end

  # factor out the clock so it's mockable in tests
  def now
    Time.now
  end
end
