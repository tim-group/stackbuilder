require 'stackbuilder/stacks/kubernetes/namespace'
require 'stackbuilder/stacks/maintainers'
require 'erb'

module Stacks::Services::K8sCronJobApp
  attr_accessor :job_schedule
  attr_accessor :jvm_args
  attr_accessor :jvm_heap

  def self.extended(object)
    object.configure
  end

  #TODO - waz - do we need a polilcy to allow initContainer to talk to Nexus like app_service? what is needed?
  # TODO - waz - need to add/share @monitor_tucker  to setup network policy if we want promothesus scraping
  def configure
    # TODO: - waz - these are now duplicated in app_service and here -
    @jvm_args = nil
    @jvm_heap = '64M'
  end

  def k8s_type
    "cronjob"
  end
  # rubocop:disable Metrics/ParameterLists
  def app_generate_resources(_app_deployer, dns_resolver, _hiera_provider, _hiera_scope, app_name, app_version, replicas, used_secrets, site, \
     _standard_labels, app_service_labels, app_resources_name, config)
    # rubocop:enable Metrics/ParameterLists
    output = []
    output << generate_app_config_map_resource(app_resources_name, app_service_labels, config) unless config.nil?

    resource_built = generate_cronjob_resource(app_resources_name, app_service_labels, app_name, app_version)
    resource_built['spec']['jobTemplate']['spec']['template']['spec']['initContainers'] =
      generate_init_container_resource(app_resources_name, app_service_labels, app_name, app_version, replicas, used_secrets, config)

    container_resource = generate_container_resource(app_name, app_version, config)
    container_resource.first['ports'] << { "containerPort" => 5000, "name" => "jmx" }
    resource_built['spec']['jobTemplate']['spec']['template']['spec']['containers'] = container_resource

    resource_built['spec']['jobTemplate']['spec']['template']['spec']['volumes'] = generate_volume_resources(app_resources_name, config)

    output << resource_built
    network_policies =  generate_app_network_policies(dns_resolver, site, app_service_labels)
    network_policies <<  create_ingress_pushgate_network_policy_from_cronjob(@environment.name, app_name, @custom_service_name,  app_service_labels)
    network_policies <<  create_egress_to_pushgate_network_policy(@environment.name, app_name, @custom_service_name, app_service_labels)
    output += network_policies
    output
  end

  def generate_cronjob_resource(resource_name, app_service_labels, app_name, app_version)
    labels = app_service_labels.merge('application' => app_name,
                                      'app.kubernetes.io/name' => app_name,
                                      'app.kubernetes.io/version' => app_version)

    annotations = {}
    annotations['maintainers'] = JSON.dump(@maintainers) unless @maintainers.empty?
    annotations['description'] = description unless @description.nil?

    cronjob_annotations = {}
    cronjob_annotations['configmap.reloader.stakater.com/reload'] = resource_name
    cronjob_annotations['secret.reloader.stakater.com/reload'] = resource_name
    cronjob_annotations.merge!(annotations)

    cronjob = {
      'apiVersion' => 'batch/v1beta1',
      'kind' => 'CronJob',
      'metadata' => {
        'name' => resource_name,
        'namespace' => @environment.name,
        'labels' => labels,
        'annotations' => cronjob_annotations
      },
      'spec' => {
        'concurrencyPolicy' => 'Forbid',
        'failedJobsHistoryLimit' => 10,
        'schedule' => @job_schedule,
        'jobTemplate' => {
          'spec' => {
            'template' => {
              'spec' => {
              }
            }
          }
        }
      }

    }
    cronjob
  end

  private

  def create_egress_to_pushgate_network_policy(env_name, app_name, service_name, standard_labels)
    pushgateway_filters = [generate_pod_and_namespace_selector_filter("monitoring",   'app' => 'prometheus-pushgateway')]
    egress_spec = [{
                       'to' => pushgateway_filters,
                       'ports' => [{
                                       'port' => '9091',
                                       'protocol' => 'TCP'
                                   }]
                   }]

    pod_selector_match_labels  =  {
        'application' => app_name,
        'machineset' => standard_labels['machineset'],
        'group' => standard_labels['group'],
        'app.kubernetes.io/component' => service_name
    }
  create_egress_network_policy("prometheus-pushgateway", env_name,
                               standard_labels, egress_spec,  pod_selector_match_labels)
  end

  def create_ingress_pushgate_network_policy_from_cronjob(env_name, app_name, service_name, standard_labels)

    #TODO -waz - remove duplication in creating ingress policy with whats in resoource_set_app
    pod_match_labels = {
        'application' => app_name,
        'machineset' => standard_labels['machineset'],
        'group' => standard_labels['group'],
        'app.kubernetes.io/component' => service_name
    }
    pod_filters = [generate_pod_and_namespace_selector_filter(env_name,  pod_match_labels)]

    spec = {
        'podSelector' => {
            'matchLabels' => {
                'app' => 'prometheus-pushgateway',
            }
        },
        'policyTypes' => [
            'Ingress'
        ],
        'ingress' => [{
                          'from' => pod_filters,
                          'ports' => [{
                                          'port' => '9091',
                                          'protocol' => 'TCP'
                                      }]
                      }]
    }

    hash = Support::DigestGenerator.from_hash(spec)

   {
        'apiVersion' => 'networking.k8s.io/v1',
        'kind' => 'NetworkPolicy',
        'metadata' => {
            'name' => "allow-prometheus-pushgateway-in-from-cronjob-#{hash}",
            'namespace' => env_name, # TODO waz should this be monitoring or the environment where pod is?
            'labels' => standard_labels
        },
        'spec' => spec
    }

  end


end
