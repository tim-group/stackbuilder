metadata :name => 'hpilo',
         :description => 'Agent that interacts with the hpilo cli allowing you to control hosts via iLO',
         :author => 'TIM Infrastructure',
         :license => '',
         :url => 'https://seveas.github.io/python-hpilo/',
         :version => 1,
         :timeout => 1200

action 'get_host_data', :description => 'Get SMBIOS records that describe the host' do
  input :host_fqdn,
        :description => 'iLO FQDN',
        :prompt => 'iLO FQDN',
        :type => :string,
        :validation => '^[a-z]{2,}-[a-z]+-[0-9]{3}\.ilo\.[a-z]+\.net.local$',
        :maxlength => 255,
        :optional => false
end

action 'power_status', :description => 'Return the power status of the host' do
  input :host_fqdn,
        :description => 'iLO FQDN',
        :prompt => 'FQDN',
        :type => :string,
        :validation => '^[a-z]{2,}-[a-z]+-[0-9]{3}\.ilo\.[a-z]+\.net.local$',
        :maxlength => 255,
        :optional => false
end

action 'power_off', :description => 'Power off the host' do
  input :host_fqdn,
        :description => 'iLO FQDN',
        :prompt => 'FQDN',
        :type => :string,
        :validation => '^[a-z]{2,}-[a-z]+-[0-9]{3}\.ilo\.[a-z]+\.net.local$',
        :maxlength => 255,
        :optional => false
end

action 'power_on', :description => 'Power on the host' do
  input :host_fqdn,
        :description => 'iLO FQDN',
        :prompt => 'FQDN',
        :type => :string,
        :validation => '^[a-z]{2,}-[a-z]+-[0-9]{3}\.ilo\.[a-z]+\.net.local$',
        :maxlength => 255,
        :optional => false
end

action 'set_one_time_boot', :description => 'Configure the host to boot one-time-only from the specified device (normally network)' do
  input :host_fqdn,
        :description => 'iLO FQDN',
        :prompt => 'FQDN',
        :type => :string,
        :validation => '^[a-z]{2,}-[a-z]+-[0-9]{3}\.ilo\.[a-z]+\.net.local$',
        :maxlength => 255,
        :optional => false

  input :device,
        :description => 'The device to boot from',
        :prompt => 'Device',
        :type => :string,
        :validation => '^(cdrom|usb|hdd|network)$',
        :maxlength => 7,
        :optional => false
end

action 'update_rib_firmware', :description => 'Update the iLO firmware for the specified host' do
  input :host_fqdn,
        :description => 'iLO FQDN',
        :prompt => 'FQDN',
        :type => :string,
        :validation => '^[a-z]{2,}-[a-z]+-[0-9]{3}\.ilo\.[a-z]+\.net.local$',
        :maxlength => 255,
        :optional => false

  input :version,
        :description => 'Version of the iLO firmware to install',
        :prompt => 'Version',
        :type => :string,
        :validation => '^((\d).(\d{1,2})|latest)$',
        :maxlength => 6,
        :optional => false
end
