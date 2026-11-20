# Phonebook on Kubernetes

A Flask phonebook running on a two-node Kubernetes cluster on AWS EC2. One service manages contacts, another searches them, and both use the same MySQL database. Terraform creates the master and worker. Traefik provides one browser address for both interfaces.

- `/` opens contact management.
- `/search` opens search.
- MySQL stores its files through a `20Gi` persistent volume at `/mnt/data` on the worker.

The Flask application is based on the ONDIA Academy / Clarusway Phonebook training project. I added the infrastructure and deployment configuration, Dockerfiles, shared browser entry point, navigation, and database connection handling. The application images are published on [Docker Hub](https://hub.docker.com/r/yazenalbu/phonebook).

## Files

- `app/web/` contains the management application and its Dockerfile.
- `app/result/` contains the search application and its Dockerfile.
- `terraform/` provisions two Ubuntu EC2 instances and bootstraps Kubernetes.
- `kubernetes/` contains the application, database, storage, configuration, and Ingress manifests.

## Create the cluster

Use an AWS account with a default VPC in `us-east-1`, authenticated AWS CLI credentials, Terraform, and an EC2 SSH key pair. The default key pair name is `linuspass`. Set the Terraform variable `key_name` if yours has a different name.

Run these commands on the machine where you manage Terraform.

```bash
git clone https://github.com/yazenAlbu/phonebook-kubernetes.git
cd phonebook-kubernetes/terraform
terraform init
terraform plan
terraform apply
terraform output -raw master_public_dns
```

When prompted for `ssh_cidr`, enter your current public IPv4 address followed by `/32`. The default configuration uses two `t3a.medium` instances with encrypted `30GiB` disks. Application ports `30001`, `30002`, and `30080` are reachable from the network set by `web_cidr`, which defaults to `0.0.0.0/0`.

Connect to the master using the DNS name from the output and the private key matching your EC2 key pair.

```bash
ssh -i /path/to/linuspass.pem ubuntu@MASTER_PUBLIC_DNS
```

Run the remaining deployment commands in the master's Ubuntu terminal. Wait for bootstrap to finish, then confirm `kube-master` and `kube-worker` are both `Ready`.

```bash
cloud-init status --wait
kubectl get nodes
sudo apt-get install -y git gettext-base
git clone https://github.com/yazenAlbu/phonebook-kubernetes.git
cd phonebook-kubernetes
```

## Deploy the application

On the first deployment, generate the database passwords and render the Secret template directly into Kubernetes. The checked-in `mysql-secret.yaml` contains environment placeholders. Keep the existing Secret when updating an initialized database so its credentials continue to match the stored MySQL data.

```bash
export MYSQL_ROOT_PASSWORD=$(openssl rand -hex 24)
export MYSQL_PASSWORD=$(openssl rand -hex 24)
envsubst '$MYSQL_ROOT_PASSWORD $MYSQL_PASSWORD' < kubernetes/mysql-secret.yaml | kubectl apply -f -
unset MYSQL_ROOT_PASSWORD MYSQL_PASSWORD
```

Apply storage and configuration, then start MySQL.

```bash
kubectl apply -f kubernetes/persistent_volume.yaml
kubectl apply -f kubernetes/persistent_volume_claim.yaml
kubectl apply -f kubernetes/database_configmap.yaml
kubectl apply -f kubernetes/servers_configmap.yaml
kubectl apply -f kubernetes/mysql_service.yaml
kubectl apply -f kubernetes/mysql_deployment.yaml
kubectl rollout status deployment/mysql --timeout=300s
```

Start management before search. The management application creates the contacts table when it starts.

```bash
kubectl apply -f kubernetes/web_server_service.yaml
kubectl apply -f kubernetes/web_server_deployment.yml
kubectl rollout status deployment/web-server --timeout=300s
kubectl apply -f kubernetes/result_server_service.yaml
kubectl apply -f kubernetes/result_server_deployment.yml
kubectl rollout status deployment/result-server --timeout=300s
```

Install the Ingress controller and routing rules.

```bash
kubectl apply -f kubernetes/ingress-controller.yaml
kubectl rollout status deployment/traefik -n ingress-system --timeout=300s
kubectl apply -f kubernetes/phonebook-ingress.yaml
kubectl get pods
kubectl get services
kubectl get ingress
```

Open `http://MASTER_PUBLIC_DNS:30080/` in a browser. The Search link opens `/search` on the same address. Terraform also prints this address as `ingress_url`. The original management and search NodePorts remain available on `30001` and `30002`. Navigation between the two interfaces uses the shared Ingress address.

## Build the images

The manifests use the published `web-v2` and `result-v2` tags. To build your own copies, run these commands from the repository root on a machine with Docker. Replace `YOUR_DOCKERHUB_USERNAME` and update the two Deployment image names before applying them.

```bash
docker login
docker build -t YOUR_DOCKERHUB_USERNAME/phonebook:web-v2 app/web
docker build -t YOUR_DOCKERHUB_USERNAME/phonebook:result-v2 app/result
docker push YOUR_DOCKERHUB_USERNAME/phonebook:web-v2
docker push YOUR_DOCKERHUB_USERNAME/phonebook:result-v2
```

## Verify the deployment

Add a test contact through management, find it through search, then update and delete it. To check storage, add another contact and replace the database pod.

```bash
kubectl delete pod -l app=mysql
kubectl rollout status deployment/mysql --timeout=300s
```

Search for the same contact after MySQL is ready again. The recreated pod mounts the existing persistent volume.

Verified on 20 November 2026 on two AWS EC2 nodes running Kubernetes `v1.35.10`. Browser checks covered adding, searching, updating, and deleting a contact through the shared Ingress address. The same contact remained searchable after deleting the MySQL pod and waiting for its replacement. Public HTTP checks passed on ports `30001`, `30002`, and `30080` on both nodes, including `/search` through Ingress.

## Clean up

Return to the original `terraform/` working directory containing the state file and run the following command. Supply `ssh_cidr` again if Terraform prompts for it.

```bash
terraform destroy
```

This removes the project instances, their disks, security group, and worker IAM resources. The hostPath database storage survives a pod replacement. Terminating the worker deletes the disk containing the lab data.

