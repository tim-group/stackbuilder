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

  def configure
    # TODO: - waz - these are now duplicated in app_service and here -
    @jvm_args = nil
    @jvm_heap = '64M'
  end

  def k8s_type
    "cronjob"
  end

  # rubocop:disable Metrics/ParameterLists
  def app_generate_resources(_app_deployer, _dns_resolver, _hiera_provider, _hiera_scope, app_name, app_version, replicas, used_secrets, _site, \
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
  def generate_app_config_map_resource(app_resources_name, app_service_labels, config)
    output = super
    output['data']['config.properties'] << "prometheus.pushgate.service=prometheus-pushgateway.monitoring\n"
    output['data']['config.properties'] << "prometheus.pushgate.port=9091\n"
    output
  end

end
