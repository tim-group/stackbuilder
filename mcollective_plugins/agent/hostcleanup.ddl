metadata    :name        => "Hostcleanup",
            :description => "Host cleanup helper",
            :author      => "TIM Group",
            :license     => "MIT",
            :version     => "1",
            :url         => "http://www.timgroup.com",
            :timeout     => 15

action "puppet_cleanup", :description => "run host_cleanup" do
    input  :fqdn,
           :prompt      => "fqdn",
           :description => "fqdn of the host to be cleaned",
           :type        => :string,
           :optional    => false,
           :maxlength   => 200,
           :validation  => ".+"
end

action "mongodb_cleanup", :description => "remove entry from mongodb" do
    input  :fqdn,
           :prompt      => "fqdn",
           :description => "fqdn of the host to be cleaned",
           :type        => :string,
           :optional    => false,
           :maxlength   => 200,
           :validation  => ".+"
end

action "nagios_cleanup", :description => "edit /etc/nagios3/conf.d/nagios_host.cfg" do
    input  :fqdn,
           :prompt      => "fqdn",
           :description => "fqdn of the host to be cleaned",
           :type        => :string,
           :optional    => false,
           :maxlength   => 200,
           :validation  => ".+"
end

action "puppet", :description => "run host_cleanup" do
    input  :fqdn,
           :prompt      => "fqdn",
           :description => "fqdn of the host to be cleaned",
           :type        => :string,
           :optional    => false,
           :maxlength   => 200,
           :validation  => ".+"
end

action "mongodb", :description => "remove entry from mongodb" do
    input  :fqdn,
           :prompt      => "fqdn",
           :description => "fqdn of the host to be cleaned",
           :type        => :string,
           :optional    => false,
           :maxlength   => 200,
           :validation  => ".+"
end

action "nagios", :description => "edit /etc/nagios3/conf.d/nagios_host.cfg" do
    input  :fqdn,
           :prompt      => "fqdn",
           :description => "fqdn of the host to be cleaned",
           :type        => :string,
           :optional    => false,
           :maxlength   => 200,
           :validation  => ".+"
end

action "all", :description => "cleanup puppet, mongodb and nagios for a given fqdn" do
    input  :fqdn,
           :prompt      => "fqdn",
           :description => "fqdn of the host to be cleaned",
           :type        => :string,
           :optional    => false,
           :maxlength   => 200,
           :validation  => ".+"
end

