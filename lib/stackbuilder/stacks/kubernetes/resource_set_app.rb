 require 'stackbuilder/stacks/kubernetes/network_policy_common'
 require 'stackbuilder/stacks/kubernetes/resource_set_ingress'

 module Stacks::Kubernetes::ResourceSetApp
   include Stacks::Kubernetes::NetworkPolicyCommon
   include Stacks::Kubernetes::ResourceSetIngress

   ##
   # Classes including this module must define the following instance variables
   #
   # @artifact_from_nexus as true/false
   #
   # @ports as a hash of hashes detailing the config of each port.
   # {
   #   A string identifier for this port. If your application is a regular service then the name form /etc/services is probably a good choice.
   # For our custom applcations serving up http use 'http'.
   #   'name' => {
   #     'port' => An Integer defining the port number
   #     'protocol' => Optional string detailing the protocol of this port. Places in the code should default to TCP if this is undefined.
   #     'service_port' => Optional Integer used to create a Kubernetes Service to expose this app
   #   }
   # }
   #
   # And the following functions
   # non_k8s_dependencies_exist?

   def use_service_account
     @enable_service_account = true
   end

   private

   # rubocop:disable Metrics/ParameterLists
   def app_generate_resources(_app_deployer, dns_resolver, hiera_provider, hiera_scope, app_name, app_version, replicas, used_secrets, site, \
     standard_labels, app_service_labels, app_resources_name, config)
     # rubocop:enable Metrics/ParameterLists
     output = []
     output << generate_app_config_map_resource(app_resources_name, app_service_labels, config) unless config.nil?
     output << generate_app_service_resource(app_resources_name, app_service_labels)
     output << generate_app_deployment_resource(app_resources_name, app_service_labels, app_name, app_version, replicas, used_secrets, config)
     output << generate_app_pod_disruption_budget_resource(app_resources_name, app_service_labels)
     output << generate_app_alerting_resource(app_resources_name, site, app_service_labels, replicas)
     output += generate_app_network_policies(dns_resolver, site, app_service_labels)
     output += generate_app_service_account_resources(dns_resolver, site, app_service_labels, app_resources_name)

     output += ingress_generate_resources(dns_resolver, hiera_provider, hiera_scope, site, \
                                          standard_labels, app_service_labels, app_resources_name, app_resources_name)

     output
   end

   def generate_app_service_resource(resource_name, labels)
     {
       'apiVersion' => 'v1',
       'kind' => 'Service',
       'metadata' => {
         'name' => resource_name,
         'namespace' => @environment.name,
         'labels' => labels
       },
       'spec' => {
         'type' => 'ClusterIP',
         'selector' => {
           'machineset' => labels['machineset'],
           'group' => labels['group'],
           'app.kubernetes.io/component' => labels['app.kubernetes.io/component'],
           'participation' => 'enabled'
         },
         'ports' => @ports.keys.select do |port_name|
           !@ports[port_name]['service_port'].nil?
         end.map do |port_name|
           port_config = {}
           port_config['name'] = port_name
           port_config['port'] = @ports[port_name]['service_port']
           port_config['protocol'] = @ports[port_name]['protocol'].nil? ? 'TCP' : @ports[port_name]['protocol'].upcase
           port_config['targetPort'] = @ports[port_name]['port']
           port_config
         end
       }
     }
   end

   # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
   def generate_app_deployment_resource(resource_name, app_service_labels, app_name, app_version, replicas, _secrets, config)
     # rubocop:enable Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity

     labels = app_service_labels.merge('application' => app_name,
                                       'app.kubernetes.io/name' => app_name,
                                       'app.kubernetes.io/version' => app_version)

     container_image = "repo.net.local:8080/timgroup/#{app_name}:#{app_version}"

     annotations = {}
     annotations['maintainers'] = JSON.dump(@maintainers) unless @maintainers.empty?
     annotations['description'] = description unless @description.nil?

     deployment_annotations = {}
     deployment_annotations['configmap.reloader.stakater.com/reload'] = resource_name
     deployment_annotations['secret.reloader.stakater.com/reload'] = resource_name
     deployment_annotations.merge!(annotations)

     pod_annotations = {}
     pod_annotations['seccomp.security.alpha.kubernetes.io/pod'] = 'runtime/default'
     pod_annotations.merge!(annotations)

     deployment = {
       'apiVersion' => 'apps/v1',
       'kind' => 'Deployment',
       'metadata' => {
         'name' => resource_name,
         'namespace' => @environment.name,
         'labels' => labels,
         'annotations' => deployment_annotations
       },
       'spec' => {
         'selector' => {
           'matchLabels' => {
             'machineset' => labels['machineset'],
             'group' => labels['group'],
             'app.kubernetes.io/component' => labels['app.kubernetes.io/component'],
             'participation' => 'enabled'
           }
         },
         'strategy' => {
           'type' => 'RollingUpdate',
           'rollingUpdate' => { # these settings allow one instance to be taken down and no extras to be created, this replicates orc
             'maxUnavailable' => 1,
             'maxSurge' => 0
           }
         },
         'progressDeadlineSeconds' => startup_alert_threshold_seconds,
         'replicas' => replicas,
         'template' => {
           'metadata' => {
             'labels' => {
               'participation' => 'enabled'
             }.merge(labels),
             'annotations' => pod_annotations
           },
           'spec' => {
             'affinity' => {
               'podAntiAffinity' => {
                 'preferredDuringSchedulingIgnoredDuringExecution' => [{
                   'podAffinityTerm' => {
                     'labelSelector' => {
                       'matchLabels' => {
                         'machineset' => labels['machineset'],
                         'group' => labels['group'],
                         'app.kubernetes.io/component' => labels['app.kubernetes.io/component']
                       }
                     },
                     'topologyKey' => 'kubernetes.io/hostname'
                   },
                   'weight' => 100
                 }]
               }
             },
             'automountServiceAccountToken' => false,
             'containers' => [{
               'securityContext' => {
                 'readOnlyRootFilesystem' => true,
                 'allowPrivilegeEscalation' => false,
                 'capabilities' => {
                   'drop' => ['ALL']
                 }
               },
               'image' => container_image,
               'name' => app_name,
               'resources' => create_app_container_resources_snippet,
               'ports' => @ports.keys.map do |port_name|
                 port_config = {}
                 port_config['name'] = port_name
                 port_config['containerPort'] = @ports[port_name]['port']
                 port_config['protocol'] = @ports[port_name]['protocol'].nil? ? 'TCP' : @ports[port_name]['protocol'].upcase
                 port_config
               end,
               'volumeMounts' => [
                 {
                   'name' => 'tmp-volume',
                   'mountPath' => '/tmp'
                 }
               ]
             }],
             'volumes' => [
               {
                 'name' => 'tmp-volume',
                 'emptyDir' => {}
               }
             ]
           }
         }
       }
     }

     if @enable_service_account
       deployment['spec']['template']['spec']['automountServiceAccountToken'] = true
       deployment['spec']['template']['spec']['serviceAccountName'] = resource_name
     end

     deployment['spec']['template']['spec']['securityContext'] = @security_context unless @security_context.nil?
     deployment['spec']['template']['spec']['containers'].first['command'] = @command unless @command.nil?
     deployment['spec']['template']['spec']['containers'].first['args'] = @args unless @args.nil?
     deployment['spec']['template']['spec']['containers'].first['lifecycle'] = {
       'preStop' => @lifecycle_pre_stop
     } unless @lifecycle_pre_stop.nil?
     deployment['spec']['template']['spec']['containers'].first['readinessProbe'] = @readiness_probe unless @readiness_probe.nil?
     deployment['spec']['template']['spec']['containers'].first['volumeMounts'] <<
       {
         'name' => 'config-volume',
         'mountPath' => '/config',
         'readOnly' => true
       } unless config.nil?
     deployment['spec']['template']['spec']['containers'].first['volumeMounts'] <<
       {
         'name' => 'log-volume',
         'mountPath' => @log_volume_mount_path
       } unless @log_volume_mount_path.nil?
     deployment['spec']['template']['spec']['volumes'] += [{
       'name' => 'config-volume',
       'emptyDir' => {}
     },
                                                           {
                                                             'name' => 'config-template',
                                                             'configMap' => { 'name' => resource_name }
                                                           }] unless config.nil?
     deployment['spec']['template']['spec']['volumes'] <<
       {
         'name' => 'log-volume',
         'emptyDir' => {}

       } unless @log_volume_mount_path.nil?
     unless @capabilities.nil?
       existing_capabilities = deployment['spec']['template']['spec']['containers'].first['securityContext']['capabilities']
       existing_capabilities['add'] = [] if existing_capabilities['add'].nil?
       @capabilities.each do |capability|
         existing_capabilities['add'] << capability unless existing_capabilities['add'].include? capability
       end
     end

     deployment
   end

   def generate_app_pod_disruption_budget_resource(resource_name, app_service_labels)
     {
       'apiVersion' => 'policy/v1beta1',
       'kind' => 'PodDisruptionBudget',
       'metadata' => {
         'name' => resource_name,
         'namespace' => @environment.name,
         'labels' => app_service_labels
       },
       'spec' => {
         'maxUnavailable' => 1,
         'selector' => {
           'matchLabels' => {
             'machineset' => app_service_labels['machineset'],
             'group' => app_service_labels['group'],
             'app.kubernetes.io/component' => app_service_labels['app.kubernetes.io/component']
           }
         }
       }
     }
   end

   def generate_app_alerting_resource(resource_name, site, app_service_labels, replicas)
     fail("app_service '#{name}' in '#{@environment.name}' requires alerts_channel (set self.alerts_channel)") if @alerts_channel.nil?

     pagerduty = page_on_critical ? { 'pagerduty' => 'true' } : {}

     rules = []

     rules << {
       'alert' => 'StatusCritical',
       'expr' => "sum(tucker_component_status{job=\"#{resource_name}\",status=\"critical\"}) by (pod, namespace) > 0",
       'labels' => {
         'severity' => 'critical',
         'alertname' => "#{resource_name} CRITICAL",
         'alert_owner_channel' => alerts_channel
       }.merge(pagerduty),
       'annotations' => {
         'message' => '{{ $value }} components are critical on {{ $labels.namespace }}/{{ $labels.pod }}',
         'status_page_url' => "https://go.timgroup.com/insight/#{site}/proxy/{{ $labels.namespace }}/{{ $labels.pod }}/info/status"
       }
     } if @monitor_tucker

     rules << {
       'alert' => 'DeploymentReplicasMismatch',
       'expr' => "kube_deployment_spec_replicas{job='kube-state-metrics', namespace='#{environment.name}', deployment='#{resource_name}'} " \
       "!= kube_deployment_status_replicas_available{job='kube-state-metrics', namespace='#{environment.name}', deployment='#{resource_name}'}",
       'for' => "#{startup_alert_threshold_seconds * replicas}s",
       'labels' => {
         'severity' => 'warning',
         'alertname' => "#{resource_name} is missing replicas",
         'alert_owner_channel' => alerts_channel
       },
       'annotations' => {
         'message' => "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has not matched the " \
           "expected number of replicas for longer than the startup_alert_threshold (#{startup_alert_threshold}) * replicas (#{replicas})."
       }
     }

     rules << {
       'alert' => 'PodCrashLooping',
       'expr' => "kube_pod_container_status_last_terminated_reason{namespace='#{environment.name}', pod=~'^#{resource_name}.*'} == 1 and " \
         "on(pod, container) rate(kube_pod_container_status_restarts_total[5m]) * 300 > 1",
       'labels' => {
         'severity' => 'critical',
         'alertname' => "#{resource_name} is stuck in a crash loop",
         'alert_owner_channel' => alerts_channel
       }.merge(pagerduty),
       'annotations' => {
         'message' => 'Pod {{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is restarting ' \
           '{{ printf "%.2f" $value }} times / 5 minutes.'
       }
     }

     rules << {
       'alert' => 'ImageRetrievalFailure',
       'expr' => "kube_pod_container_status_waiting_reason{reason=~'^(ErrImagePull|ImagePullBackOff|InvalidImageName)$', " \
         "namespace='#{environment.name}', pod=~'^#{resource_name}.*'} == 1",
       'labels' => {
         'severity' => 'warning',
         'alertname' => "#{resource_name} is failing to retrieve the requested image",
         'alert_owner_channel' => alerts_channel
       },
       'annotations' => {
         'message' => 'Pod {{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is failing to retrieve ' \
           'the requested image.'
       }
     }

     if @monitor_readiness_probe
       rules << {
         'alert' => 'FailedReadinessProbe',
         'expr' => "(((time() - kube_pod_start_time{pod=~\".*#{resource_name}.*\"}) > #{startup_alert_threshold_seconds}) "\
             "and on(pod) (rate(prober_probe_total{probe_type=\"Readiness\",result=\"failed\",pod=~\"^#{resource_name}.*\"}[1m]) > 0))",
         'labels' => {
           'severity' => 'warning',
           'alertname' => "#{resource_name} failed readiness probe when deployment not in progress",
           'alert_owner_channel' => alerts_channel
         },
         'annotations' => {
           'message' => '{{ $labels.namespace }}/{{ $labels.pod }} has failed readiness probe when deployment not in progress',
           'status_page_url' => "https://go.timgroup.com/insight/#{site}/proxy/#{@environment.name}/{{ $labels.pod }}/info/status"
         }
       }
     end

     {
       'apiVersion' => 'monitoring.coreos.com/v1',
       'kind' => 'PrometheusRule',
       'metadata' => {
         'labels' => {
           'prometheus' => 'main',
           'role' => 'alert-rules'
         }.merge(app_service_labels),
         'name' => resource_name,
         'namespace' => @environment.name
       },
       'spec' => {
         'groups' => [
           {
             'name' => 'stacks-alerts',
             'rules' => rules
           }
         ]
       }
     }
   end

   def generate_app_network_policies(dns_resolver, site, standard_labels)
     # this method only does the network policies for the app pods
     network_policies = []

     network_policies += create_network_policies_for_dependants(dns_resolver, site, standard_labels)
     network_policies += create_network_policies_for_dependencies(dns_resolver, site, standard_labels)
     network_policies += create_app_network_policies_to_nexus(dns_resolver, standard_labels)
     network_policies += create_app_network_policies_from_prometheus(standard_labels)

     network_policies
   end

   def create_network_policies_for_dependants(_dns_resolver, site, standard_labels)
     important_dependants = []
     network_policies = []

     if non_k8s_dependencies_exist?
       ingress_selector = {
         'machineset' => name,
         'group' => @groups.first,
         'app.kubernetes.io/component' => 'ingress'
       }
       ingress_filters = [generate_pod_and_namespace_selector_filter(@environment.name, ingress_selector)]
       network_policies << create_ingress_network_policy_for_internal_service(@environment.short_name, "#{name}-#{@groups.first}-ing",
                                                                              @environment.name, standard_labels,
                                                                              ingress_filters)

       important_dependants = dependants.select { |dep| dep.from.kubernetes }
     else
       important_dependants = dependants
     end

     important_dependants.each do |dep|
       vs = dep.from
       is_same_site = dep.requirement == :same_site
       next if is_same_site && !vs.exists_in_site?(vs.environment, site)

       match_labels = {
         'machineset' => vs.name,
         'group' => vs.groups.first,
         'app.kubernetes.io/component' => vs.custom_service_name
       }

       filters = [generate_pod_and_namespace_selector_filter(vs.environment.name, match_labels)]
       network_policies << create_ingress_network_policy_for_internal_service(vs.environment.short_name, vs.short_name,
                                                                              @environment.name, standard_labels, filters)
     end

     network_policies
   end

   def generate_app_service_account_resources(dns_resolver, site, standard_labels, service_account_name)
     return [] unless @enable_service_account
     resources = [{
       'apiVersion' => 'v1',
       'kind' => 'ServiceAccount',
       'metadata' => {
         'name' => service_account_name,
         'namespace' => @environment.name,
         'labels' => standard_labels
       }
     }]

     network_policy_spec = {
       'podSelector' => {
         'matchLabels' => {
           'machineset' => standard_labels['machineset'],
           'group' => standard_labels['group'],
           'app.kubernetes.io/component' => @custom_service_name
         }
       },
       'policyTypes' => [
         'Egress'
       ],

       'egress' => [{
         'to' => [{
           'ipBlock' => {
             'cidr' => "#{dns_resolver.lookup("#{site}-kube-apiserver-vip.mgmt.#{site}.net.local")}/32"
           }
         }],
         'ports' => [{
           'protocol' => 'TCP',
           'port' => 6443
         }]
       }]
     }

     hash = Support::DigestGenerator.from_hash(network_policy_spec)

     resources << {
       'apiVersion' => 'networking.k8s.io/v1',
       'kind' => 'NetworkPolicy',
       'metadata' => {
         'name' => "allow-out-to-#{site}-kubernetes-api-#{hash}",
         'namespace' => @environment.name,
         'labels' => standard_labels
       },
       'spec' => network_policy_spec
     }
   end

   def create_network_policies_for_dependencies(dns_resolver, site, standard_labels)
     network_policies = []
     dependencies.each do |dep|
       next if dep.is_a?(Stacks::Dependencies::EnvironmentDependency)

       case dep.to_selector
       when Stacks::Dependencies::ServiceSelector
         dep.resolve_targets(@environment).each do |vs|
           network_policies << create_egress_to_specific_service(vs, dns_resolver, site, standard_labels)
         end
       when Stacks::Dependencies::AllKubernetesSelector
         network_policies << create_egress_network_policy(
           'all',
           @environment.name,
           standard_labels,
           [
             {
               'to' => [{
                 'podSelector' => {
                   'matchLabels' => {
                     'app.kubernetes.io/component' => @custom_service_name
                   }
                 },
                 'namespaceSelector' => {
                   'matchLabels' => {
                     'isStacksEnvironment' => 'true'
                   }
                 }
               }],
               'ports' => @ports.keys.map do |port_name|
                 {
                   'protocol' => @ports[port_name]['protocol'].nil? ? 'TCP' : @ports[port_name]['protocol'].upcase,
                   'port' => port_name
                 }
               end
             }],
           'machineset' => standard_labels['machineset'],
           'group' => standard_labels['group'],
           'app.kubernetes.io/component' => @custom_service_name)
       when Stacks::Dependencies::LabelsKubernetesSelector
         network_policies << create_egress_network_policy(
           'labels',
           @environment.name,
           standard_labels,
           [
             {
               'to' => [{
                 'podSelector' => {
                   'matchLabels' => dep.to_selector.labels
                 },
                 'namespaceSelector' => {
                   'matchLabels' => {
                     'isStacksEnvironment' => 'true'
                   }
                 }
               }],
               'ports' => @ports.keys.map do |port_name|
                 {
                   'protocol' => @ports[port_name]['protocol'].nil? ? 'TCP' : @ports[port_name]['protocol'].upcase,
                   'port' => port_name
                 }
               end
             }],
           'machineset' => standard_labels['machineset'],
           'group' => standard_labels['group'],
           'app.kubernetes.io/component' => standard_labels['app.kubernetes.io/component'])
       end
     end
     network_policies
   end

   def create_egress_to_specific_service(vs, dns_resolver, site, standard_labels)
     fail "Dependency '#{vs.name}' is not supported for k8s - endpoints method is not implemented" if !vs.respond_to?(:endpoints)

     chosen_site_of_vs = vs.exists_in_site?(vs.environment, site) ? site : vs.environment.primary_site
     endpoints = vs.endpoints(self, chosen_site_of_vs)

     egresses = []
     if vs.kubernetes
       match_labels = {
         'machineset' => vs.name,
         'group' => vs.groups.first,
         'app.kubernetes.io/component' => @custom_service_name
       }
       egresses << {
         'to' => [
           generate_pod_and_namespace_selector_filter(vs.environment.name, match_labels)
         ],
         'ports' => [{
           'protocol' => 'TCP',
           'port' => 'app'
         }]
       }
     else
       endpoints.each do |e|
         ip_blocks = []
         e[:fqdns].uniq.each do |fqdn|
           ip_blocks << { 'ipBlock' => { 'cidr' => "#{dns_resolver.lookup(fqdn)}/32" } }
         end
         egresses << {
           'to' => ip_blocks,
           'ports' => [{
             'protocol' => 'TCP',
             'port' => e[:port]
           }]
         }
       end
     end
     app_service_match_labels = {
       'machineset' => standard_labels['machineset'],
       'group' => standard_labels['group'],
       'app.kubernetes.io/component' => @custom_service_name
     }

     create_egress_network_policy("#{vs.environment.short_name}-#{vs.short_name}", @environment.name,
                                  standard_labels, egresses, app_service_match_labels)
   end

   def create_app_network_policies_to_nexus(dns_resolver, standard_labels)
     fail('The class including this module must define instance variable @artifact_from_nexus as true or false, probaly in its configure method') \
       if @artifact_from_nexus.nil?
     return [] unless @artifact_from_nexus
     network_policies = []
     nexus_filters = [{
       'to' => [{ 'ipBlock' => { 'cidr' => "#{dns_resolver.lookup('office-nexus-001.mgmt.lon.net.local')}/32" } }],
       'ports' => @ports.keys.map do |_port_name|
         {
           'protocol' => 'TCP',
           'port' => 8080
         }
       end
     }]
     ingress_match_labels = {
       'machineset' => standard_labels['machineset'],
       'group' => standard_labels['group'],
       'app.kubernetes.io/component' => @custom_service_name
     }
     network_policies << create_egress_network_policy('off-nexus', @environment.name, standard_labels,
                                                      nexus_filters, ingress_match_labels)
   end

   def create_app_network_policies_from_prometheus(standard_labels)
     network_policies = []
     prom_filters = [generate_pod_and_namespace_selector_filter('monitoring', 'prometheus' => 'main')]
     network_policies << create_ingress_network_policy_for_internal_service('mon', 'prom-main',
                                                                            @environment.name, standard_labels,
                                                                            prom_filters) if @monitor_tucker
     network_policies
   end

   def create_ingress_network_policy_for_internal_service(virtual_service_env, virtual_service_name, env_name, labels, filters)
     spec = {
       'podSelector' => {
         'matchLabels' => {
           'machineset' => labels['machineset'],
           'group' => labels['group'],
           'app.kubernetes.io/component' => @custom_service_name
         }
       },
       'policyTypes' => [
         'Ingress'
       ],
       'ingress' => [{
         'from' => filters,
         'ports' => @ports.keys.map do |port_name|
           {
             'protocol' => @ports[port_name]['protocol'].nil? ? 'TCP' : @ports[port_name]['protocol'].upcase,
             'port' => port_name
           }
         end
       }]
     }

     hash = Support::DigestGenerator.from_hash(spec)

     {
       'apiVersion' => 'networking.k8s.io/v1',
       'kind' => 'NetworkPolicy',
       'metadata' => {
         'name' => "allow-in-from-#{virtual_service_env}-#{virtual_service_name}-#{hash}",
         'namespace' => env_name,
         'labels' => labels
       },
       'spec' => spec
     }
   end

   def container_image(app_name, app_version)
     "repo.net.local:8080/timgroup/#{app_name}:#{app_version}"
   end

   def create_app_container_resources_snippet
     ephemeral_storage_limit = @ephemeral_storage_size ? { 'ephemeral-storage' => @ephemeral_storage_size } : {}

     cpu_request = @cpu_request ? { 'cpu' => @cpu_request } : {}
     cpu_limit = @cpu_limit ? { 'cpu' => @cpu_limit } : {}

     {
       'limits' => {
         'memory' => scale_memory(memory_limit)
       }.merge(ephemeral_storage_limit).merge(cpu_limit),
       'requests' => {
         'memory' => scale_memory(memory_limit)
       }.merge(ephemeral_storage_limit).merge(cpu_request)
     }
   end

   def scale_memory(memory, coeff = 0)
     m = memory.match(/^(\d+)(G|M|K)i?$/)
     byte_conversion_factor = case m.captures[1].upcase
                              when 'G'
                                1024**3
                              when 'M'
                                1024**2
                              when 'K'
                                1024
                              end
     bytes = (1 + coeff) * m.captures[0].to_i * byte_conversion_factor
     "#{(bytes / 1024).floor}Ki"
   end
 end
