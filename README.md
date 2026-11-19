# Phonebook on Kubernetes

A Flask phonebook deployed on a two-node Kubernetes cluster on AWS EC2, provisioned with Terraform. The management service creates, updates, and deletes contacts. The search service reads the same MySQL database.

- `terraform/`: EC2 infrastructure and control-plane and worker bootstrap scripts.
- `kubernetes/`: Persistent storage, MySQL, and the two application deployments and services.

I verified the deployment by adding a test contact and finding it through the search page using VS Code port forwarding. MySQL uses a persistent volume backed by `/mnt/data` on the worker. The persistence of a record across a database restart was not tested.

## Reproduce the lab

1. In `terraform/`, run `terraform init`, `terraform plan`, and `terraform apply`. Provide your public IPv4 address with `/32` when prompted for `ssh_cidr`. The configuration expects an EC2 key pair named `linuspass` in `us-east-1`; change `keyname` in `main.tf` to use your own.
2. Connect to the master and confirm both nodes are ready with `kubectl get nodes`. Copy the `kubernetes/` directory to the master and run the remaining commands there.
3. Create the `mysql-secret` Secret in the default namespace with the keys `MYSQL_ROOT_PASSWORD` and `MYSQL_PASSWORD`. Create the Docker Hub pull Secret `phonebook-registry` in the same namespace. Supply credentials separately from this repository. The manifests reference `yazenalbu/phonebook:web-v1` and `yazenalbu/phonebook:result-v1`; update `image:` if you built your own copies.
4. Apply the two storage files, `database_configmap.yaml`, `mysql_deployment.yaml`, and `mysql_service.yaml`. Wait for `kubectl rollout status deployment/mysql` to succeed. Apply `web-server.yaml`, wait for `kubectl rollout status deployment/web-server`, and then apply `result-server.yaml`. The management app initializes the table used by search.
5. From two master terminals, run `kubectl port-forward service/web-server 8081:80` and `kubectl port-forward service/result-server 8082:80`. Forward both ports in VS Code Remote and open the displayed local addresses.

The original Flask application comes from the ONDIA Academy / Clarusway Phonebook training project. The repository contains the infrastructure and deployment configuration. The container images are hosted in [`yazenalbu/phonebook`](https://hub.docker.com/r/yazenalbu/phonebook).
