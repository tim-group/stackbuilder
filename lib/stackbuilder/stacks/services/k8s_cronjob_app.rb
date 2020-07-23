require 'stackbuilder/stacks/kubernetes/namespace'
require 'stackbuilder/stacks/maintainers'
require 'erb'

module Stacks::Services::K8sCronJobApp
  def k8s_type
    "cronjob"
  end
  # rubocop:disable Metrics/ParameterLists
  def app_generate_resources(_app_deployer, _dns_resolver, _hiera_provider, _hiera_scope, app_name, app_version, _replicas, _used_secrets, _site, \
     _standard_labels, app_service_labels, app_resources_name, _config)
    # rubocop:enable Metrics/ParameterLists
    output = []
    output << generate_cronjob_resource(app_resources_name, app_service_labels, app_name, app_version)

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
        'schedule' => '*/1 * * * *'
      }

    }
    pp cronjob
    cronjob
  end
end
