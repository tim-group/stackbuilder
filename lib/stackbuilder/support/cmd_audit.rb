module CMDAudit
  def audit(_argv)
    site = $environment.options[:primary_site]
    logger(Logger::DEBUG) { ":primary_site for \"#{$environment.name}\" is \"#{site}\"" }

    @total = Hash.new(0)
    @total_str = lambda { |a, b| sprintf("%d/%d %2.0f%%", a, b, 100.0 * a / b) }

    hosts = details_for($factory.host_repository.find_compute_nodes(site).hosts)
    kvm_hosts_tabulate(hosts, site)
  end

  private

  def order(headers)
    headers.inject([]) do |order, header|
      case header
      when :fqdn                        then order[0] = header
      when :vms                         then order[1] = header
      when 'memory(GB)'.to_sym          then order[2] = header
      when 'os(GB)'.to_sym              then order[3] = header
      when 'data(GB)'.to_sym            then order[4] = header
      when 'allocation disabled'.to_sym then order[5] = header
      when 'tags'.to_sym                then order[6] = header
      else order.push(header)
      end
      order
    end.select { |header| !header.nil? }
  end

  def kvm_hosts_tabulate_sum_totals(header, value)
    return 0 if value.size == 0

    total_width = 0
    case header.to_s
    when 'vms'
      @total[:vms] += value.to_i
      total_width = @total[:vms].to_s.size
    when 'memory(GB)'
      re = /^(\d+)\/(\d+)/.match(value)
      @total[:mem_used] += re[1].to_i
      @total[:mem_avail] += re[2].to_i
      total_width = @total_str.call(@total[:mem_used], @total[:mem_avail]).to_s.size
    when 'os(GB)'
      re = /^\w+: (\d+)\/(\d+)/.match(value)
      @total[:os_used] += re[1].to_i
      @total[:os_avail] += re[2].to_i
      total_width = @total_str.call(@total[:os_used], @total[:os_avail]).to_s.size
    when 'data(GB)'
      re = /^\w+: (\d+)\/(\d+)/.match(value)
      @total[:data_used] += re[1].to_i
      @total[:data_avail] += re[2].to_i
      total_width = @total_str.call(@total[:data_used], @total[:data_avail]).to_s.size
    end
    total_width + 1
  end

  def self.included(receiver)
    require 'collimator'
    include Collimator
    receiver.send :include, Collimator
  end
  # XXX output not very pretty, percentages not aligned
  def kvm_hosts_tabulate(data, site)
    require 'set'

    all_headers = data.inject(Set.new) { |acc, (_fqdn, header)| acc.merge(header.keys) }

    ordered_headers = order(all_headers)
    header_widths = data.sort.inject({}) do |ordered_header_widths, (_fqdn, data_values)|
      row = ordered_headers.inject([]) do |row_values, header|
        value = data_values[header] || ""

        # determine greatest width
        total_width = kvm_hosts_tabulate_sum_totals(header, value)
        width = value.size > header.to_s.size ? value.size + 1 : header.to_s.size + 1
        width = total_width > width ? total_width : width
        if !ordered_header_widths.key?(header)
          ordered_header_widths[header] = width
        else
          ordered_header_widths[header] = width if ordered_header_widths[header] < width
        end
        row_values << value
        row_values
      end
      Table.row(row)
      ordered_header_widths
    end
    total_list = [
      "total",
      "#{@total[:vms]}",
      @total_str.call(@total[:mem_used], @total[:mem_avail]),
      @total_str.call(@total[:os_used], @total[:os_avail])
    ]
    # data(GB) not present in env=dev
    total_list.push(@total_str.call(@total[:data_used], @total[:data_avail])) if @total[:data_avail] > 0
    Table.row(total_list)

    Table.header("KVM host machines audit for site: #{site}")
    ordered_headers.each do |header|
      width = header_widths[header] rescue header.to_s.size
      Table.column(header.to_s, :width => width, :padding => 1, :justification => :left)
    end
    Table.tabulate
  end

  def details_for(hosts)
    hosts.inject({}) do |data, host|
      stats = stats_for(host)
      data[host.fqdn] = stats
      data
    end
  end

  def stats_for(host)
    ram_stats = convert_hash_values_from_kb_to_gb(StackBuilder::Allocator::PolicyHelpers.ram_stats_of(host))
    storage_stats = convert_hash_values_from_kb_to_gb(StackBuilder::Allocator::PolicyHelpers.storage_stats_of(host))
    vm_stats = StackBuilder::Allocator::PolicyHelpers.vm_stats_of(host)
    allocation_tags_host = StackBuilder::Allocator::PolicyHelpers.allocation_tags_of(host)
    allocation_status = StackBuilder::Allocator::PolicyHelpers.allocation_status_of(host)
    merge = [storage_stats_to_string(storage_stats), vm_stats, ram_stats_to_string(ram_stats), allocation_status, allocation_tags_host]
    merged_stats = Hash[*merge.map(&:to_a).flatten]
    merged_stats[:fqdn] = host.fqdn
    merged_stats
  end

  def convert_hash_values_from_kb_to_gb(result_hash)
    gb_hash = result_hash.each.inject({}) do |result, (key, value)|
      if value.is_a?(Hash)
        result[key] = convert_hash_values_from_kb_to_gb(value)
      elsif value.is_a?(String) || value.is_a?(Symbol)
        result[key] = value
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

  def ram_stats_to_string(ram_stats)
    used = ram_stats[:allocated_ram]
    total = ram_stats[:host_ram]
    used_percentage = "#{(used.to_f / total.to_f * 100).round.to_s.rjust(3)}%" rescue 0
    { 'memory(GB)'.to_sym => "#{used}/#{total} #{used_percentage}" }
  end

  def storage_stats_to_string(storage_stats)
    storage_stats.inject({}) do |stats, (storage_type, value_hash)|
      arch = value_hash[:arch]
      used = value_hash[:used]
      total = value_hash[:total]
      used_percentage = "#{(used.to_f / total.to_f * 100).round}%" rescue 0
      stats["#{storage_type}(GB)".to_sym] = "#{arch}: #{used}/#{total} #{used_percentage}"
      stats
    end
  end
end
