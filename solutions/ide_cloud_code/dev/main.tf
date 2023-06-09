# Reference:
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network
resource "google_compute_network" "dev_network" {
  name                    = var.vpcNetworkName
  description             = "Developer network"
  auto_create_subnetworks = false
}

# Reference:
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_subnetwork
resource "google_compute_subnetwork" "dev_subnet" {
  name          = var.vpcSubnetName
  ip_cidr_range = "10.128.0.0/16"
  region        = var.gcp_region
  network       = google_compute_network.dev_network.id
}

# Reference:
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall
resource "google_compute_firewall" "serverless-to-vpc-connector" {
  name          = "serverless-to-vpc-connector"
  network       = google_compute_network.dev_network.name
  source_ranges = ["107.178.230.64/26", "35.199.224.0/19"]
  direction     = "INGRESS"

  # Enable INGRESS
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["667"]
  }

  allow {
    protocol = "udp"
    ports    = ["665-666"]
  }

  # source_tags = ["web"]
  target_tags = ["vpc-connector"]

  depends_on = [google_compute_network.dev_network]
}

resource "google_compute_firewall" "vpc-connector-to-serverless" {
  name               = "vpc-connector-to-serverless"
  network            = google_compute_network.dev_network.name
  destination_ranges = ["107.178.230.64/26", "35.199.224.0/19"]
  direction          = "EGRESS"

  # Enable EGRESS
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["667"]
  }

  allow {
    protocol = "udp"
    ports    = ["665-666"]
  }

  target_tags = ["vpc-connector"]

  depends_on = [google_compute_network.dev_network]
}


resource "google_compute_firewall" "vpc-connector-health-check" {
  name          = "vpc-connector-health-check"
  network       = google_compute_network.dev_network.name
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16", "108.170.220.0/23"]
  direction     = "INGRESS"

  # Enable INGRESS
  allow {
    protocol = "tcp"
    ports    = ["667"]
  }

  target_tags = ["vpc-connector"]

  depends_on = [google_compute_network.dev_network]
}


resource "google_compute_firewall" "vpc-connector-egress" {
  name      = "vpc-connector-egress"
  network   = google_compute_network.dev_network.name
  direction = "INGRESS"

  # Enable INGRESS
  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_tags = ["vpc-connector"]

  depends_on = [google_compute_network.dev_network]
}



# Reference:
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/vpc_access_connector

# Enable the vpc access service
resource "google_project_service" "vpcaccess-api" {
  project = var.gcp_project_id
  service = "vpcaccess.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  # disable_dependent_services = true
}

resource "google_vpc_access_connector" "connector" {
  provider      = google-beta
  name          = "ideconn"
  region        = var.gcp_region
  network       = google_compute_network.dev_network.name
  ip_cidr_range = "10.8.0.0/28"

  # Note: valid options: f1-micro, e2-micro, e2-standard-4
  machine_type = var.vpcConnectorMachineType

  depends_on = [
    google_project_service.vpcaccess-api, google_compute_network.dev_network
  ]
}


# Reference:
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/cloud_run_service
#
# Enable the Cloud Run service
resource "google_project_service" "run" {
  project = var.gcp_project_id
  service = "run.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  # disable_dependent_services = true
}


resource "google_cloud_run_service" "ide" {
  name     = var.gcrIDEService
  # location = var.gcrRegion
  location = var.gcp_region

  template {
    spec {
      containers {
        image = "gcr.io/qwiklabs-resources/ide-proxy:latest"
      }
      container_concurrency = 2
    }

    # Add support for vpc connector
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = "3"
        "autoscaling.knative.dev/minScale"        = "1"
        "run.googleapis.com/vpc-access-egress"    = "all"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.connector.name
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  # Dependency - Cloud Run API enabled
  # depends_on = [google_project_service.run]
  depends_on = [google_project_service.run, google_compute_instance.default]
}


data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.ide.location
  project  = google_cloud_run_service.ide.project
  service  = google_cloud_run_service.ide.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_target_instance
data "google_compute_image" "image_family" {
  family  = var.gceMachineImage
  project = "qwiklabs-resources"
}


# Reference:
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance
#
resource "google_compute_instance" "default" {

  name         = var.gceInstanceName
  machine_type = var.gceMachineType
  zone         = var.gceInstanceZone

  tags = var.gceInstanceTags

  boot_disk {
    initialize_params {
      image = data.google_compute_image.image_family.self_link
    }
  }

  network_interface {
    # network       = google_compute_network.dev_network.name
    subnetwork = google_compute_subnetwork.dev_subnet.name

    access_config {
      // Ephemeral IP
    }
  }

  # Add Key/Value pair e.g. SSH keys here
  # metadata = {
  #  foo = "bar"
  # }

  # metadata_startup_script = "echo Welcome to Octopus > /tmp/octopus.txt"

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    # email  = google_service_account.default.email
    scopes = var.gceInstanceScope
  }

  # Dependency - VPC Access connector 
  depends_on = [google_vpc_access_connector.connector]
}


# Reference:
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/using_gke_with_terraform
#

##---------------------------------------------------------------------------
## Container Cluster: Separate Managed Node Pool Example

# GKE cluster
resource "google_container_cluster" "primary" {
  provider    = google-beta
  name        = var.gkeClusterName
  location    = var.gkeLocation
  description = "dev cluster for testing"

  # Define VPC configuration
  network    = var.gkeIsCustomNetwork ? var.gkeNetwork : null 
  subnetwork = var.gkeIsCustomNetwork ? var.gkeSubnetwork : null 

  # Set networking mode
  # IP Alias requires VPC Native
  networking_mode = var.gkeIsPrivateCluster ? var.gkeModeVpcNative : var.gkeModeRoutes 

  ## NOTE: Set null value where false value is set
  # Set this value if not using GKE Autopilot
  #initial_node_count = var.gkeInitialNodeCount ? var.gkeInitialNodeCount : null
  initial_node_count = var.gkeIsAutopilot ? null : var.gkeInitialNodeCount

  ## NOTE: Set null value where false value is set
  # Condition setting to variable. If defined set to variable, otherwise default to false 
  enable_binary_authorization = var.gkeIsBinAuth ? var.gkeIsBinAuth : null 
  
  ## NOTE: Set null value where false value is set
  # Condition setting to variable. If defined set to variable, default to false
  enable_autopilot            = var.gkeIsAutopilot ? var.gkeIsAutopilot : null 

  private_cluster_config {
    enable_private_endpoint = var.gkeIsPrivateCluster
    enable_private_nodes    = var.gkeIsPrivateCluster ? var.gkeIsPrivateCluster : null 
    master_ipv4_cidr_block  = var.gkeIsPrivateCluster ? var.gkeMasterIPv4CIDRBlock : null
  }
    
  master_authorized_networks_config {
#    cidr_blocks {
#      cidr_block   = var.gkeIsPrivateCluster ? "0.0.0.0/0" : null
#      display_name = var.gkeIsPrivateCluster ? "Open-Access" : null
#    }
  }

#  addons_config {
#     disabled = var.istio_disabled
#     auth     = var.istio_auth
#  }


  ## TODO: Need to refine this 
  # Enable Alias IPs
  ip_allocation_policy {
##    cluster_ipv4_cidr_block  = var.gkeIsPrivateCluster ? "/14" : null
##    services_ipv4_cidr_block = var.gkeIsPrivateCluster ? "/20" : null
  }

  # Release channel GKE clusters.
  release_channel {
    channel = "STABLE"
  }

  # Dependency - Cloud Run API enabled
  ##   depends_on = [google_compute_instance.default]
}
