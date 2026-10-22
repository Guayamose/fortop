#!/usr/bin/env ruby
require "json"
require "open3"

directory = File.expand_path(__dir__)
config = JSON.parse(File.read(File.join(directory, "config.json")))
project = config.fetch("project")
raise "Unexpected project" unless project == "fortop-ai-gkecke"

def run!(*arguments)
  puts arguments.join(" ")
  system(*arguments, exception: true)
end

gcloud = [ "gcloud", "--project=#{project}", "--quiet" ]
def ensure_resource(gcloud, describe, create)
  _, error, status = Open3.capture3(*gcloud, *describe, "--format=value(name)")
  return if status.success?
  raise error unless error.match?(/NOT_FOUND|not found|does not exist/i)
  run!(*gcloud, *create)
end

run!(*gcloud, "services", "enable", "compute.googleapis.com", "artifactregistry.googleapis.com", "secretmanager.googleapis.com", "iap.googleapis.com")
ensure_resource(gcloud, [ "compute", "networks", "describe", config["network"] ],
  [ "compute", "networks", "create", config["network"], "--subnet-mode=custom", "--bgp-routing-mode=regional" ])
ensure_resource(gcloud, [ "compute", "networks", "subnets", "describe", config["subnet"], "--region=#{config['region']}" ],
  [ "compute", "networks", "subnets", "create", config["subnet"], "--network=#{config['network']}", "--region=#{config['region']}", "--range=10.42.0.0/24", "--enable-private-ip-google-access" ])
ensure_resource(gcloud, [ "compute", "firewall-rules", "describe", "fortop-web" ],
  [ "compute", "firewall-rules", "create", "fortop-web", "--network=#{config['network']}", "--direction=INGRESS", "--allow=tcp:80,tcp:443", "--source-ranges=0.0.0.0/0", "--target-tags=fortop" ])
ensure_resource(gcloud, [ "compute", "firewall-rules", "describe", "fortop-iap-ssh" ],
  [ "compute", "firewall-rules", "create", "fortop-iap-ssh", "--network=#{config['network']}", "--direction=INGRESS", "--allow=tcp:22", "--source-ranges=35.235.240.0/20", "--target-tags=fortop" ])

service_account = "#{config['service_account']}@#{project}.iam.gserviceaccount.com"
ensure_resource(gcloud, [ "iam", "service-accounts", "describe", service_account ],
  [ "iam", "service-accounts", "create", config["service_account"], "--display-name=Fortop production runtime" ])
gemini_account = "fortop-gemini@#{project}.iam.gserviceaccount.com"
ensure_resource(gcloud, [ "iam", "service-accounts", "describe", gemini_account ],
  [ "iam", "service-accounts", "create", "fortop-gemini", "--display-name=Fortop Gemini" ])
run!(*gcloud, "projects", "add-iam-policy-binding", project, "--member=serviceAccount:#{gemini_account}", "--role=roles/aiplatform.user", "--condition=None", "--format=none")
ensure_resource(gcloud, [ "artifacts", "repositories", "describe", config["repository"], "--location=#{config['region']}" ],
  [ "artifacts", "repositories", "create", config["repository"], "--location=#{config['region']}", "--repository-format=docker", "--description=Fortop production images" ])
run!(*gcloud, "artifacts", "repositories", "add-iam-policy-binding", config["repository"], "--location=#{config['region']}", "--member=serviceAccount:#{service_account}", "--role=roles/artifactregistry.reader", "--condition=None", "--format=none")
run!(*gcloud, "artifacts", "repositories", "set-cleanup-policies", config["repository"], "--location=#{config['region']}", "--policy=#{directory}/registry-cleanup.json", "--no-dry-run")
ensure_resource(gcloud, [ "secrets", "describe", config["secret"] ],
  [ "secrets", "create", config["secret"], "--replication-policy=user-managed", "--locations=#{config['region']}" ])

bucket = "gs://#{config['backup_bucket']}"
ensure_resource(gcloud, [ "storage", "buckets", "describe", bucket ],
  [ "storage", "buckets", "create", bucket, "--location=#{config['region']}", "--uniform-bucket-level-access", "--public-access-prevention" ])
run!(*gcloud, "storage", "buckets", "update", bucket, "--lifecycle-file=#{directory}/backup-lifecycle.json", "--soft-delete-duration=0")
run!(*gcloud, "storage", "buckets", "add-iam-policy-binding", bucket, "--member=serviceAccount:#{service_account}", "--role=roles/storage.objectCreator", "--format=none")
ensure_resource(gcloud, [ "compute", "addresses", "describe", config["address"], "--region=#{config['region']}" ],
  [ "compute", "addresses", "create", config["address"], "--region=#{config['region']}", "--network-tier=PREMIUM" ])
ip, error, status = Open3.capture3(*gcloud, "compute", "addresses", "describe", config["address"], "--region=#{config['region']}", "--format=value(address)")
raise error unless status.success?
ip = ip.strip

ensure_resource(gcloud, [ "compute", "instances", "describe", config["instance"], "--zone=#{config['zone']}" ],
  [ "compute", "instances", "create", config["instance"], "--zone=#{config['zone']}", "--machine-type=#{config['machine_type']}",
    "--subnet=#{config['subnet']}", "--address=#{ip}", "--tags=fortop", "--service-account=#{service_account}", "--scopes=cloud-platform",
    "--image-family=debian-12", "--image-project=debian-cloud", "--boot-disk-size=30GB", "--boot-disk-type=pd-balanced", "--no-boot-disk-auto-delete",
    "--create-disk=name=fortop-data,size=40GB,type=pd-standard,auto-delete=no,device-name=fortop-data",
    "--shielded-secure-boot", "--deletion-protection", "--metadata=enable-oslogin=TRUE,block-project-ssh-keys=TRUE,disable-legacy-endpoints=TRUE",
    "--metadata-from-file=startup-script=#{directory}/startup.sh", "--labels=app=fortop,environment=production,managed-by=fortop-infra" ])

username, error, status = Open3.capture3(*gcloud, "compute", "os-login", "describe-profile", "--format=value(posixAccounts[0].username)")
raise error unless status.success?
production = config.merge("ip" => ip, "host" => "fortop.#{ip.tr('.', '-')}.sslip.io", "ssh_user" => username.strip)
File.write(File.join(directory, "production.json"), JSON.pretty_generate(production) + "\n")
puts "Fortop project: #{project}; production URL: https://#{production['host']}"
