module CMDFindRogue
  def self.get_defined_machines(environment)
    e = []
    environment.environments.each { |_envname, env| e += env.flatten }
    hostnames = e.map(&:hostname)
    machines = e.map(&:to_spec)
    [hostnames, machines]
  end

  def self.get_allocated_machines(sites)
    hostnames = []
    domains = Hash[]
    storage = Hash[]
    sites.each do |site|
      compute_nodes = $factory.host_repository.find_compute_nodes(site, true).hosts
      hostnames += compute_nodes.map(&:allocated_machines).flatten.map { |vm| vm[:hostname] }
      domains.merge!(compute_nodes.map(&:domains).reduce({}, :merge))
      storage[site] = compute_nodes.map(&:storage) # list of hashes, don't merge in case there are duplicates
    end
    [hostnames, domains, storage]
  end

  def self.rogue_check_allocation(defined_hostnames, allocated_hostnames)
    # rogue1 = defined_hostnames - allocated_hostnames
    # puts sprintf("defined, but not allocated (%d):", rogue1.size)
    # rogue1.each { |node| puts "  #{node}" }

    rogue2 = allocated_hostnames - defined_hostnames
    puts sprintf("allocated, but not defined (%d):", rogue2.size)
    rogue2.each { |node| puts "  #{node}" }
  end

  private

  # rubocop:disable Style/Next
  def self.rogue_check_resources(defined_machines, allocated_domains)
    puts "checking vm properties..."
    allocated_domains.each do |afqdn, adata|
      dhost = defined_machines.detect { |dh| sprintf("%s.%s", dh[:hostname], dh[:domain]) == afqdn }
      next if dhost.nil?

      if dhost[:vcpus].to_i != adata[:vcpus]
        if dhost[:vcpus].to_i != 0
          puts sprintf("  %s.%s: defined cpus: %d; reality: %d", dhost[:hostname], dhost[:domain],
                       dhost[:vcpus], adata[:vcpus])
          # else
          # XXX how to figure out the default value?
        end
      end

      if dhost[:ram].to_i != adata[:memory]
        if dhost[:ram].to_i != 0
          puts sprintf("  %s.%s: defined memory: %d; reality: %d", dhost[:hostname], dhost[:domain],
                       dhost[:ram], adata[:memory])
          # else
          # XXX how to figure out the default value?
        end
      end
    end
  end

  # XXX incomplete, too many special cases. return to this once everything is migrated to NNI
  def self.rogue_check_missing_storage(defined_machines, allocated_storage, _allocated_hostnames)
    puts "checking missing or misallocated storage..."
    defined_machines.each do |dhost|
      dhost[:storage].each do |mount_point, p|
        if allocated_storage[dhost[:fabric]].nil?
          puts "  fabric \"#{dhost[:fabric]}\" has no storage allocated at all"
          next
        end

        astorage = []
        allocation_name = dhost[:hostname] + mount_point.to_s.gsub('/', '_').gsub(/_$/, '')
        allocated_storage[dhost[:fabric]].each do |as|
          if as[p[:type]].nil?
            puts "  #{dhost[:hostname]}: no storage type \"#{p[:type]}\" on fabric \"#{dhost[:fabric]}\" allocated"
            next
          end
          a = as[p[:type]][:existing_storage][allocation_name.to_sym]
          astorage << a if !a.nil?
        end

        if astorage.size != 1
          puts "  #{dhost[:hostname]}: storage \"#{allocation_name}\" found on #{astorage.size} compute nodes"
          next
        end

        astorage_size = astorage[0]
        psize = p[:size].to_i * 1024 * 1024
        if astorage_size.to_i == psize
          puts "  #{dhost[:hostname]}: size for storage \"#{allocation_name}\" is \"#{astorage_size}\", expected " \
            "\"#{psize * 1024 / 1000}\" -- was this vm created manually?"
          next
        end

        psize = p[:size].to_i * 1024 * 1024 * 1024 / 1000
        if astorage_size.to_i != psize
          puts "  #{dhost[:hostname]}: size mismatch for storage \"#{allocation_name}\", is \"#{astorage_size}\", " \
            "should be \"#{psize}\""
          next
        end
      end
    end
  end
  # rubocop:enable Style/Next
end
