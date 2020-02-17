metadata    :name        => "deployapp",
            :description => "Deploys applications and reports on their status",
            :author      => "David Ellis",
            :license     => "Apache License 2.0",
            :version     => "0.9",
            :url         => "",
            :timeout     => 300

action "status", :description => "Returns the status" do
    output :status,
           :description => "Status",
           :display_as => "Status"

end

action "get_artifact", :description => "Retrieve an artifact without restarting the application" do
    output :logs,
           :description => "returns the logs from the deployment tool",
           :display_as => "Get Artifact"
end

action "update_to_version", :description => "Installs a new version of an application" do
    output :logs,
           :description => "returns the logs from the deployment tool",
           :display_as => "Update To Version"
end

action "enable_participation", :description => "Enable participation" do
    output :logs,
           :description => "returns the logs from the deployment tool",
           :display_as => "Enable Participation"
end

action "disable_participation", :description => "Disable participation" do
    output :logs,
           :description => "returns the logs from the deployment tool",
           :display_as => "Disable Participation"
end

action "stop", :description => "Stop the instance" do
    output :logs,
           :description => "",
           :display_as => "Stop the instance"
end

action "restart", :description => "Restart the instance" do
    output :logs,
           :description => "",
           :display_as => "Restart the instance"
end

action "kill", :description => "Hard kill the instance" do
    output :logs,
           :description => "",
           :display_as => "Hard kill the instance"
end

