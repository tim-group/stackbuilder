module CMDAuditVms
  def audit_vms(_argv)
    site = @environment.options[:primary_site]
    logger(Logger::DEBUG) { ":primary_site for \"#{@environment.name}\" is \"#{site}\"" }

    vms = {}

    @factory.host_repository.find_vms(site).each { |vm| vms[vm[:fqdn]] = { :vm_name => vm[:fqdn].partition('.').first, :actual => vm } }

    vms.values.group_by { |data| data[:actual][:host_fqdn] }.each do |host_fqdn, host_vms|
      vm_fqdn_by_vm_name = host_vms.map { |data| [data[:vm_name], data[:actual][:fqdn]] }.to_h
      specs = vm_fqdn_by_vm_name.values.map { |vm_fqdn| @factory.inventory.find(vm_fqdn) }.reject(&:nil?).map(&:to_spec)
      @factory.compute_node_client.check_vm_definitions(host_fqdn, specs).each do |host_result|
        host_result[1].each do |vm_name, vm_result|
          vm_fqdn = vm_fqdn_by_vm_name[vm_name]
          inconsistency_count = (vm_result[0] == 'success') ? 0 : vm_result[1].lines.count - 1
          vms[vm_fqdn].merge!(:inconsistency_count => inconsistency_count)
        end
      end
    end

    get_specified_vms(site).each do |machine_def|
      fqdn = machine_def.mgmt_fqdn
      vms[fqdn] = {} if vms[fqdn].nil?
      vms[fqdn].merge!(:vm_name => machine_def.hostname, :spec => machine_def.to_spec, :spec_os => machine_def.lsbdistcodename)
    end

    vms_stats = vms.map { |fqdn, vm| vm_stats_for(fqdn, vm) }
    render_vm_stats(vms_stats)
  end

  private

  def get_specified_vms(site)
    specified_vms = []
    @factory.inventory.environments.sort.each do |_envname, env|
      specified_vms += env.flatten.select { |vm| vm.site == site }
    end
    specified_vms
  end

  def vm_stats_for(vm_fqdn, vm)
    result = { :fqdn => vm_fqdn, :vm_name => vm[:vm_name], :inconsistency_count => vm[:inconsistency_count] }

    if vm[:spec]
      result[:specified_ram] = convert_kb_to_gb(vm[:spec][:ram])
      result[:specified_os_disk] = total_spec_storage_size(vm[:spec][:storage], 'os')
      result[:specified_data_disk] = total_spec_storage_size(vm[:spec][:storage], 'data')
      result[:specified_cpus] = vm[:spec][:vcpus].to_i
      result[:specified_os] = vm[:spec_os]
    end

    if vm[:actual]
      result[:host_fqdn] = vm[:actual][:host_fqdn]
      result[:days_since_provisioned] = convert_epoch_time_to_days_ago(vm[:actual].fetch(:facts, {})['provision_secs_since_epoch'])
      uptime_days = vm[:actual].fetch(:facts, {})['uptime_days']
      result[:days_since_restarted] = uptime_days.nil? ? nil : "#{uptime_days}d"
      result[:actual_os] = vm[:actual].fetch(:facts, {})['lsbdistcodename']
      result[:actual_ram] = convert_kb_to_gb(vm[:actual][:max_memory])
      result[:actual_os_disk] = total_logical_volume_size(vm[:actual][:logical_volumes], 'disk1')
      result[:actual_data_disk] = total_logical_volume_size(vm[:actual][:logical_volumes], 'disk2')
      result[:actual_cpus] = vm[:actual][:vcpus]
    end

    result
  end

  def total_spec_storage_size(storage, type)
    size_strings = storage.values.select { |s| s[:type] == type }.map do |s|
      if s[:prepare] && s[:prepare][:options] && s[:prepare][:options][:guest_lvm_pv_size]
        s[:prepare][:options][:guest_lvm_pv_size]
      else
        s[:size]
      end
    end
    size_strings.inject(0) { |a, e| a + e.chomp('G').to_i }
  end

  def total_logical_volume_size(lvs, vg_name)
    bytes = lvs.select { |lv| lv[:vg_name] == vg_name }.inject(0) { |a, e| a + e[:lv_size] }
    convert_bytes_to_gb(bytes)
  end

  def convert_kb_to_gb(value)
    value.to_i / (1024 * 1024)
  end

  def convert_bytes_to_gb(value)
    value.to_i / (1024 * 1024 * 1024)
  end

  def convert_epoch_time_to_days_ago(epoch_time)
    return nil if epoch_time.nil?
    begin
      days_ago = (Time.now.to_i - epoch_time.to_i) / (60 * 60 * 24)
      "#{days_ago}d"
    rescue StandardError
      nil
    end
  end

  def render_vm_stats(vms_stats)
    host_col_width = vms_stats.map { |x| x[:vm_name] }.map(&:length).max
    printf("%-#{host_col_width}s%12s%8s%6s%10s%10s%16s%7s%7s%9s\n",
           "vm", "host", "ram", "cpus", "os_disk", "data_disk", "os", "age", "uptime", "diff_cnt")
    vms_stats.sort_by { |a| vm_sort_key(a) }.each do |stats|
      printf("%-#{host_col_width}s", stats[:vm_name])
      print_result(12, domain_name_from_fqdn(stats[:host_fqdn]), !stats[:host_fqdn].nil?)
      print_formatted_pair(8, stats[:specified_ram], stats[:actual_ram])
      print_formatted_pair(6, stats[:specified_cpus], stats[:actual_cpus])
      print_formatted_pair(10, stats[:specified_os_disk], stats[:actual_os_disk])
      print_formatted_pair(10, stats[:specified_data_disk], stats[:actual_data_disk])
      print_formatted_pair(16, stats[:specified_os], stats[:actual_os])
      print_result(7, stats[:days_since_provisioned], happy_days(stats[:days_since_provisioned]))
      print_result(7, stats[:days_since_restarted], happy_days(stats[:days_since_restarted]))
      print_result(9, stats[:inconsistency_count], stats[:inconsistency_count] == 0)
      printf("\n")
    end
    printf("All figures are reported as specified/actual\n")
  end

  def print_formatted_pair(width, specified, actual)
    print_result(width, "#{specified.nil? ? 'X' : specified}/#{actual.nil? ? 'X' : actual}", specified == actual)
  end

  def print_result(width, value, is_good)
    colour = is_good ? "[0;32m" : "[0;31m"
    printf("#{colour}%#{width}s[0m", value.nil? ? 'X' : value)
  end

  def happy_days(daystring)
    !daystring.nil? && daystring.to_i <= 365
  end

  def domain_name_from_fqdn(fqdn)
    fqdn.nil? ? nil : fqdn.partition('.').first
  end

  def vm_sort_key(vm_stats)
    [
      vm_stats[:actual_ram].nil? ? -vm_stats[:specified_ram] : -vm_stats[:actual_ram],
      vm_stats[:actual_data_disk].nil? ? -vm_stats[:specified_data_disk] : -vm_stats[:actual_data_disk],
      vm_stats[:actual_os_disk].nil? ? -vm_stats[:specified_os_disk] : -vm_stats[:actual_os_disk],
      vm_stats[:fqdn]
    ]
  end
end
