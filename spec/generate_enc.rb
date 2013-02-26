
enc_for("ci-refapp-005.mgmt.st.net.local")

accept do |machine_def|
  generate_appserver(machine_def) do
    {'role::http_app_server'=> {
        :app => machine_def.app,
        :env => machine_def.environment.name,
        :vip_fqdn => machine_def.virtual_service.fqdn}
    }
  end
end

