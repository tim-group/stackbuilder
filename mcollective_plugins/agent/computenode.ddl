metadata    :name        => "computenode",
            :description => "",
            :author      => "",
            :license     => "",
            :version     => "",
            :url         => "",
            :timeout     => 10000

action "launch", :description => "" do
    display :always
end

action "clean", :description => "" do
    display :always
end

action "allocate_ips", :description => "" do
    display :always
end

action "free_ips", :description => "" do
    display :always
end

action "add_cnames", :description => "" do
    display :always
end

action "remove_cnames", :description => "" do
    display :always
end

action "check_definition", :description => "" do
    display :always
    input :ignore_safe_vm_diffs,
          :prompt      => "Should ignore safe VM XML diffs?",
          :description => "Whether to ignore safe VM XML diffs",
          :type        => :boolean,
          :optional    => true
end

action "create_storage", :description => "" do
    display :always
end

action "archive_persistent_storage", :description => "" do
    display :always
end

action "enable_live_migration", :description => "" do
    display :always
    input :other_host,
          :prompt      => "Other Host",
          :description => "The host being migrated from/to",
          :type        => :string,
          :validation  => '^[a-zA-Z\-_.\d]+$',
          :optional    => false,
          :maxlength   => 128

    input :direction,
          :prompt      => "Direction",
          :description => "Direction of migration: either inbound or outbound",
          :type        => :list,
          :list        => ["inbound", "outbound"],
          :optional    => false
end

action "disable_live_migration", :description => "" do
    display :always
    input :other_host,
          :prompt      => "Other Host",
          :description => "The host being migrated from/to",
          :type        => :string,
          :validation  => '^[a-zA-Z\-_.\d]+$',
          :optional    => false,
          :maxlength   => 128

    input :direction,
          :prompt      => "Direction",
          :description => "Direction of migration: either inbound or outbound",
          :type        => :list,
          :list        => ["inbound", "outbound"],
          :optional    => false
end

action "live_migrate_vm", :description => "" do
    display :always
    input :other_host,
          :prompt      => "Dest Host",
          :description => "The destination host",
          :type        => :string,
          :validation  => '^[a-zA-Z\-_.\d]+$',
          :optional    => false,
          :maxlength   => 128

    input :vm_name,
          :prompt      => "VM Name",
          :description => "The name of the vm being migrated",
          :type        => :string,
          :validation  => '^[a-zA-Z\-_\d]+$',
          :maxlength   => 128,
          :optional    => false
end

action "check_live_vm_migration", :description => "" do
    display :always
    input :vm_name,
          :prompt      => "VM Name",
          :description => "The name of the vm being migrated",
          :type        => :string,
          :validation  => '^[a-zA-Z\-_\d]+$',
          :maxlength   => 128,
          :optional    => false
end

action "enable_allocation", :description => "" do
    display :always
end

action "disable_allocation", :description => "" do
    display :always
    input :reason,
          :prompt      => "Reason",
          :description => "The reason for disabling allocation",
          :type        => :string,
          :maxlength   => 256,
          :validation  => '^[a-zA-Z ,.;:\_\d]+$',
          :optional    => false
end
