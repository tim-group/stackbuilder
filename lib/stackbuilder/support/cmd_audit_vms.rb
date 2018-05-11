module CMDAuditVms
  def audit_vms(_argv)
    site = @environment.options[:primary_site]
    logger(Logger::DEBUG) { ":primary_site for \"#{@environment.name}\" is \"#{site}\"" }

    vms = {}

    @factory.host_repository.find_vms(site).each { |vm| vms[vm[:fqdn]] = { :actual => vm } }

    get_specified_vms(site).each do |machine_def|
      fqdn = "#{machine_def.hostname}.#{machine_def.domain}"
      vms[fqdn] = {} if vms[fqdn].nil?
      vms[fqdn].merge!({ :spec => machine_def.to_spec })
    end

    vms_stats = vms.map { |fqdn, vm| stats_for(fqdn, vm) }
    render(vms_stats)
  end

  private

  def get_specified_vms(site)
    specified_vms = []
    @factory.inventory.environments.sort.each do |_envname, env|
      specified_vms += env.flatten.select { |vm| vm.site == site }
    end
    specified_vms
  end

  def stats_for(vm_fqdn, vm)
    result = { :fqdn => vm_fqdn }

    if vm[:spec]
      result[:specified_ram] = kb_to_gb(vm[:spec][:ram])
      result[:specified_os_disk] = total_spec_storage_size(vm[:spec][:storage], 'os')
      result[:specified_data_disk] = total_spec_storage_size(vm[:spec][:storage], 'data')
      result[:specified_cpus] = vm[:spec][:vcpus].nil? ? 2 : vm[:spec][:vcpus].to_i
    end

    if vm[:actual]
      result[:actual_ram] = kb_to_gb(vm[:actual][:max_memory])
      result[:actual_os_disk] = total_logical_volume_size(vm[:actual][:logical_volumes], 'disk1')
      result[:actual_data_disk] = total_logical_volume_size(vm[:actual][:logical_volumes], 'disk2')
      result[:actual_cpus] = vm[:actual][:vcpus]
    end

    result
  end

  def total_spec_storage_size(storage, type)
    size_strings = storage.values.select { |s| s[:type] == type }.map { |s| s[:size] }
    size_strings.inject(0) { |tot, size_string| tot + size_string.chomp('G').to_i }
  end

  def total_logical_volume_size(lvs, vg_name)
    bytes = lvs.select { |lv| lv[:vg_name] == vg_name }.inject(0) { |sum, lv| sum + lv[:lv_size] }
    bytes_to_gb(bytes)
  end

  def kb_to_gb(value)
    value.to_i / (1024 * 1024)
  end

  def bytes_to_gb(value)
    value.to_i / (1024 * 1024 * 1024)
  end

  def render(vms_stats)
    printf("%-60s %10s %10s %10s %10s\n", "fqdn (spec/actual)", "ram", "cpus", "os disk", "data disk")
    vms_stats.sort_by { |a| sort_key(a) }.each do |stats|
      printf("%-60s", stats[:fqdn])
      print_formatted_pair(stats[:specified_ram], stats[:actual_ram])
      print_formatted_pair(stats[:specified_cpus], stats[:actual_cpus])
      print_formatted_pair(stats[:specified_os_disk], stats[:actual_os_disk])
      print_formatted_pair(stats[:specified_data_disk], stats[:actual_data_disk])
      printf("\n")
    end
  end

  def print_formatted_pair(specified, actual)
    colour = specified == actual ? "[0;32m" : "[0;31m"
    printf("%s%10s%s", colour, "#{specified}/#{actual}", "[0m")
  end

  def sort_key(vm_stats)
    [
        vm_stats[:actual_ram].nil? ? -vm_stats[:specified_ram] : -vm_stats[:actual_ram],
        vm_stats[:actual_data_disk].nil? ? -vm_stats[:specified_data_disk] : -vm_stats[:actual_data_disk],
        vm_stats[:actual_os_disk].nil? ? -vm_stats[:specified_os_disk] : -vm_stats[:actual_os_disk]
    ]
  end
end
