metadata    :name        => "nagsrv",
            :description => "Manipulate nagios servers using the ruby-nagios library",
            :author      => "crazed",
            :version     => "0.1",
            :license     => 'Apache 2.0',
            :url         => 'github.com/crazed/mcollective-nagsrv',
            :timeout     => 120

[ "enable-notify", "disable-notify", "acknowledge", "unacknowledge" ].each do |act|
  action act, :description => "Run an external command in nagios to #{act} a service" do

    user_optional = true

    if act == "acknowledge"
      user_optional = false
      input :ackreason,
          :prompt      => "reason for acknowledging",
          :description => "the reason for an acknowledgement",
          :type        => :string,
          :validation  => '^.+$',
          :maxlength   => 120,
          :optional    => false
   end

    input :user,
        :prompt      => "user performing the action",
        :description => "user performing the action",
        :type        => :string,
        :validation  => '^.+$',
        :maxlength   => 30,
        :optional    => user_optional

    input :acknowledged,
        :prompt      => "limit to acknowledged services",
        :description => "list only services that have been acknowledged",
        :type        => :string,
        :validation  => '^.+$',
        :maxlength   => 30,
        :optional    => true

    input :action,
        :prompt      => "template for ruby-nagios",
        :description => "template that can contain ${host}, ${tstamp}, and ${service}",
        :type        => :string,
        :validation  => '^.+$',
        :maxlength   => 30,
        :optional    => true

    input :forhost,
        :prompt      => "limit to matching hosts",
        :description => "a regex or full hostname that limits results",
        :type        => :string,
        :validation  => '^.+$',
        :maxlength   => 90,
        :optional    => true

    input :listhosts,
        :prompt      => "show hostnames",
        :description => "show hostnames as the result rather than services (default)",
        :type        => :string,
        :validation  => '^.+$',
        :maxlength   => 30,
        :optional    => true

    input :listservices,
        :prompt      => "show service descriptions",
        :description => "show services descriptions rather than host names",
        :type        => :string,
        :validation  => '^.+$',
        :maxlength   => 30,
        :optional    => true

    input :notifyenable,
        :prompt      => "notification enabled",
        :description => "limit results to services with notifications enabled",
        :type        => :string,
        :validation  => '^.+$',
        :maxlength   => 30,
        :optional    => true

    input :withservice,
        :prompt      => "limit to matching services",
        :description => "a regex to match against service descriptions",
        :type        => :string,
        :validation  => '^.+$',
        :maxlength   => 30,
        :optional    => true
  end
end

action "info", :description => "return basic info about services" do
  output :info,
         :description => "Info gathered from nagios",
         :display_as => "Info"
end

action "schedule_host_downtime", :description => "schedules downtime for a specified host." do
  input :host,
      :prompt      => 'Host FQDN',
      :description => 'Fully qualified domain name of host to schedule downtime for',
      :type        => :string,
      :validation  => '(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{0,62}[a-zA-Z0-9]\.)+[a-zA-Z]{2,63}$)',
      :optional    => false,
      :maxlength   => 1024

  input :duration,
      :prompt      => 'Duration',
      :description => 'Length of scheduled downtime in seconds',
      :type        => :integer,
      :optional    => false,
      :default     => 60
end

action "del_host_downtime", :description => "reinstate a host that has been scheduled for downtime" do
  input :host,
      :prompt      => 'Host FQDN',
      :description => 'Fully qualified domain name of host to cancel downtime for',
      :type        => :string,
      :validation  => '(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{0,62}[a-zA-Z0-9]\.)+[a-zA-Z]{2,63}$)',
      :optional    => false,
      :maxlength   => 1024
end

action "schedule_forced_host_svc_checks", :description => "schedules host svc checks for a specified host." do
  input :host,
      :prompt      => 'Host FQDN',
      :description => 'Fully qualified domain name of host to schedule svc checks for',
      :type        => :string,
      :validation  => '(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{0,62}[a-zA-Z0-9]\.)+[a-zA-Z]{2,63}$)',
      :optional    => false,
      :maxlength   => 1024

  input :check_time,
      :prompt      => 'Check Time',
      :description => 'When to perform checks, specified as epoch time',
      :type        => :integer,
      :optional    => true
end

action "schedule_forced_host_check", :description => "schedules host check for a specified host." do
  input :host,
      :prompt      => 'Host FQDN',
      :description => 'Fully qualified domain name of host to schedule check for',
      :type        => :string,
      :validation  => '(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{0,62}[a-zA-Z0-9]\.)+[a-zA-Z]{2,63}$)',
      :optional    => false,
      :maxlength   => 1024

  input :check_time,
      :prompt      => 'Check Time',
      :description => 'When to perform check, specified as epoch time',
      :type        => :integer,
      :optional    => true
end