module CMDAuditVms
  def audit_vms(_argv)
    site = @environment.options[:primary_site]
    logger(Logger::DEBUG) { ":primary_site for \"#{@environment.name}\" is \"#{site}\"" }

    vms = {}

    @factory.host_repository.find_vms(site).each { |vm| vms[vm[:fqdn]] = { :actual => vm } }

    vms.values.group_by { |data| data[:actual][:host_fqdn] }.each do |host_fqdn, host_vms|
      vm_fqdn_by_vm_name = host_vms.map { |data| [data[:actual][:fqdn].partition('.').first, data[:actual][:fqdn]] }.to_h
      specs = vm_fqdn_by_vm_name.keys.map { |vm_name| @factory.inventory.find_by_hostname(vm_name).to_spec }
      @factory.compute_node_client.check_vm_definitions(host_fqdn, specs).each do |host_result|
        host_result[1].each do |vm_name, vm_result|
          vm_fqdn = vm_fqdn_by_vm_name[vm_name]
          inconsistency_count = (vm_result[0] == 'success') ? 0 : vm_result[1].lines.count - 1
          vms[vm_fqdn].merge!(:inconsistency_count => inconsistency_count)
        end
      end
    end

    get_specified_vms(site).each do |machine_def|
      fqdn = "#{machine_def.hostname}.#{machine_def.domain}"
      vms[fqdn] = {} if vms[fqdn].nil?
      vms[fqdn].merge!(:spec => machine_def.to_spec)
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
    result = { :fqdn => vm_fqdn, :inconsistency_count => vm[:inconsistency_count] }

    if vm[:spec]
      result[:specified_ram] = convert_kb_to_gb(vm[:spec][:ram])
      result[:specified_os_disk] = total_spec_storage_size(vm[:spec][:storage], 'os')
      result[:specified_data_disk] = total_spec_storage_size(vm[:spec][:storage], 'data')
      result[:specified_cpus] = vm[:spec][:vcpus].to_i
    end

    if vm[:actual]
      result[:host_fqdn] = vm[:actual][:host_fqdn]
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

  def render_vm_stats(vms_stats)
    printf("%-60s %-11s%8s%6s%10s%10s%9s\n", "fqdn", "host", "ram", "cpus", "os_disk", "data_disk", "diff_cnt")
    vms_stats.sort_by { |a| vm_sort_key(a) }.each do |stats|
      printf("%-60s %-11s", stats[:fqdn], stats[:host_fqdn].nil? ? "X" : stats[:host_fqdn][/[^.]+/])
      print_formatted_pair(8, stats[:specified_ram], stats[:actual_ram])
      print_formatted_pair(6, stats[:specified_cpus], stats[:actual_cpus])
      print_formatted_pair(10, stats[:specified_os_disk], stats[:actual_os_disk])
      print_formatted_pair(10, stats[:specified_data_disk], stats[:actual_data_disk])
      print_result(9, stats[:inconsistency_count].nil? ? 'X' : stats[:inconsistency_count], stats[:inconsistency_count] == 0)
      printf("\n")
    end
    printf("All figures are reported as specified/actual\n")
  end

  def print_formatted_pair(width, specified, actual)
    print_result(width, "#{specified.nil? ? 'X' : specified}/#{actual.nil? ? 'X' : actual}", specified == actual)
  end

  def print_result(width, value, is_good)
    colour = is_good ? "[0;32m" : "[0;31m"
    printf("#{colour}%#{width}s[0m", value)
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
