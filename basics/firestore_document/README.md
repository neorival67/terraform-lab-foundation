# Terraform: Cloud Firestore Document

Create a Terraform configuration

## Using Input Values 

__NOTE:__ Qwiklabs requires some values to be defined as part of the provisioning process. 

#### Qwiklabs Properties
```
gcp_project_id = "my-gcp-project"
gcp_region     = "us-central1"
gcp_zone       = "us-central1-a"
```

## Custom Properties
```
gfd_collection_id = "mycollection" 
gfd_document_id   = "mydocument" 
gfd_document_data = { default= {"field_1"= {"stringValue"="Test"}} } 
```

## Example

View the [example configuration](https://github.com/CloudVLab/terraform-lab-foundation/tree/main/basics/firestore_document/example) to get started.

## Accessing Output Values 

N/A

## Adding a Commit 

Commits to the repository will initiate the automated QA process

It is highly recommended that modules are tested locally before making a commit.

## Request a Pull Request

__DO NOT__ raise a PR on code that does not pass integration tests.
