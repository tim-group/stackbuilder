module CMDAudit
  def audit(_argv)
    site = $environment.options[:primary_site]
    logger(Logger::DEBUG) { ":primary_site for \"#{$environment.name}\" is \"#{site}\"" }

    # FIXME: This is not sane
    @units = 'GiB' # used in totals
    @total = Hash.new(0)
    @total_str = lambda { |a, b| sprintf("%d/%d %2.0f%%", a, b, 100.0 * a / b) }
    @total_str_with_units = lambda { |a, b| sprintf("%d/%d #{@units} %2.0f%%", a, b, 100.0 * a / b) }

    hosts_raw = $factory.host_repository.find_compute_nodes(site).hosts
    hosts_stats = hosts_raw.inject({}) do |data, host|
      data[host.fqdn] = stats_for(host)
      data
    end

    hosts_stats_rendered = hosts_stats.inject({}) do |data, (fqdn, stats)|
      data[fqdn] = render_stats(fqdn, stats)
      data
    end

    kvm_hosts_tabulate(hosts_stats_rendered, site)
  end

  private

  # FIXME: This is not sane
  def kvm_hosts_tabulate_sum_totals(header, value)
    return 0 if value.size == 0

    total_width = 0
    case header.to_s
    when 'vms'
      @total[header.to_sym] += value.to_i
      total_width = @total[header.to_sym].to_s.size
    when 'vcpus'
      re = /^(\d+)\/(\d+)/.match(value)
      @total[:vcpu_used] += re[1].to_i
      @total[:vcpu_avail] += re[2].to_i
      total_width = @total_str.call(@total[:vcpu_used], @total[:vcpu_avail]).to_s.size
    when 'memory'
      re = /^(\d+)\/(\d+)\s(\w)/.match(value)
      @total[:mem_used] += re[1].to_i
      @total[:mem_avail] += re[2].to_i
      total_width = @total_str_with_units.call(@total[:mem_used], @total[:mem_avail]).to_s.size
    when 'storage_os'
      re = /^(\d+)\/(\d+)\s(\w)/.match(value)
      @total[:os_used] += re[1].to_i
      @total[:os_avail] += re[2].to_i
      total_width = @total_str_with_units.call(@total[:os_used], @total[:os_avail]).to_s.size
    when 'storage_data'
      re = /^(\d+)\/(\d+)\s(\w)/.match(value)
      @total[:data_used] += re[1].to_i
      @total[:data_avail] += re[2].to_i
      total_width = @total_str_with_units.call(@total[:data_used], @total[:data_avail]).to_s.size
    end
    total_width + 1
  end

  def self.included(receiver)
    require 'collimator'
    include Collimator
    receiver.send :include, Collimator
  end

  def kvm_hosts_tabulate(hosts, site)
    headers = [:fqdn, :vms, :vcpus, :memory, :storage_os, :storage_data, :status, :tags]
    header_width = hosts.sort.inject({}) do |header_widths, (_fqdn, values)|
      row = headers.inject([]) do |row_values, header|
        value = values[header] || ""

        # determine greatest width
        total_width = kvm_hosts_tabulate_sum_totals(header, value)
        width = value.size > header.to_s.size ? value.size + 1 : header.to_s.size + 1
        width = total_width > width ? total_width : width
        if !header_widths.key?(header)
          header_widths[header] = width
        else
          header_widths[header] = width if header_widths[header] < width
        end
        row_values << value
        row_values
      end
      Table.row(row)
      header_widths
    end
    # FIXME: This is not sane
    total_list = [
      "total",
      @total[:vms],
      @total_str.call(@total[:vcpu_used], @total[:vcpu_avail]),
      @total_str_with_units.call(@total[:mem_used], @total[:mem_avail]),
      @total_str_with_units.call(@total[:os_used], @total[:os_avail]),
      @total_str_with_units.call(@total[:data_used], @total[:data_avail])
    ]
    # storage_data not present in env=dev
    total_list.push(@total_str.call(@total[:hosts_used], @total[:hosts_avail])) if @total[:hosts_avail] > 0
    Table.row(total_list)

    Table.header("KVM host machines audit for site: #{site}")
    headers.each do |header|
      width = header_width[header] rescue header.to_s.size
      Table.column(header.to_s, :width => width, :padding => 1, :justification => :left)
    end
    Table.tabulate
  end

  def details_for(hosts)
    hosts.inject({}) do |data, host|
      data[host.fqdn] = stats_for(host)
      data
    end
  end

  def render_stats(fqdn, stats)
    merge = [
      storage_stats_to_string(stats[:storage]),
      { :vms         => stats[:vms] },
      ram_stats_to_string(stats[:memory]),
      vcpu_stats_to_string(stats[:vcpus]),
      { :status      => stats[:status] },
      { :tags        => stats[:tags] }
    ]
    merged_stats = Hash[*merge.map(&:to_a).flatten]
    merged_stats[:fqdn] = fqdn
    merged_stats
  end

  def stats_for(host)
    ram_stats = convert_hash_values_from_kb_to_gb(StackBuilder::Allocator::PolicyHelpers.ram_stats_of(host))
    storage_stats = convert_hash_values_from_kb_to_gb(StackBuilder::Allocator::PolicyHelpers.storage_stats_of(host))
    vm_stats = StackBuilder::Allocator::PolicyHelpers.vm_stats_of(host)
    cpu_stats = StackBuilder::Allocator::PolicyHelpers.vcpu_usage(host)
    allocation_tags_host = StackBuilder::Allocator::PolicyHelpers.allocation_tags_of(host)
    allocation_status = StackBuilder::Allocator::PolicyHelpers.allocation_status_of(host)
    [
      { :memory  => ram_stats },
      { :storage => storage_stats },
      { :vcpus => cpu_stats },
      vm_stats,
      allocation_tags_host,
      allocation_status
    ].inject(&:merge)
  end

  def convert_hash_values_from_kb_to_gb(result_hash)
    gb_hash = result_hash.each.inject({}) do |result, (key, value)|
      if value.is_a?(Hash)
        result[key] = convert_hash_values_from_kb_to_gb(value)
      elsif value.is_a?(String) || value.is_a?(Symbol)
        if key == :unit
          result[key] = 'GiB'
        else
          result[key] = value
        end
      else
        result[key] = kb_to_gb(value).to_f.floor
      end
      result
    end
    gb_hash
  end

  def kb_to_gb(value)
    (value.to_f / (1024 * 1024) * 100).round / 100.0
  end

  def ram_stats_to_string(stats)
    used = stats[:allocated_ram]
    unit = stats[:unit]
    total = stats[:host_ram]
    used_percentage = "#{(used.to_f / total.to_f * 100).round}" rescue 0
    { :memory => sprintf('%03d/%03d %s %02d%%', used, total, unit, used_percentage) }
  end

  def vcpu_stats_to_string(stats)
    used = stats[:allocated_vcpu]
    total = stats[:host_vcpu]
    used_percentage = "#{(used.to_f / total.to_f * 100).round}" rescue 0
    { :vcpus => sprintf('%02d/%02d %02d%%', used, total, used_percentage) }
  end

  def storage_stats_to_string(storage_stats)
    storage_stats.inject({}) do |stats, (storage_type, value_hash)|
      unit = 'GiB'
      used = value_hash[:used]
      total = value_hash[:total]
      used_percentage = "#{(used.to_f / total.to_f * 100).round}" rescue 0
      stats["storage_#{storage_type}".to_sym] = sprintf('%03d/%03d %s %02d%%', used, total, unit, used_percentage)
      stats
    end
  end
end
