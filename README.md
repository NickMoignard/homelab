# homelab

This is a mono repository for my homelab setup. It is a work in progress and will be updated as I add more nodes, services and features. I use kubernetes at work and much prefer to it over Proxmox or other hypervisors for managing workloads. Primarily because of the ease of scaling and managing complex deployments with Operators & Helm Charts.

## Hardware

I acquired multiple second-hand workstation pc's which have been upgraded with old components and some new storage drives. These have been connected together with a 1Gb/s unmanaged network switch (all i have on hand for now).

- 1 Old Dell laptop is running as a **Kubernetes control plane** node.
- 2 Old workstations are running as **Kubernetes compute worker** nodes.
- 1 Old workstation is running as a **Kubernetes storage worker** node.
- 1 Old Gaming PC with a nvidea GTX 1080 graphics card is running as a **Kubernetes compute / storage worker** node. 
  - This will be used to assist with machine learning workloads.

### OS

Each server has [**Talos Linux**](https://github.com/siderolabs/talos) installed. A lightweight Linux distribution designed for Kubernetes and other cloud-native workloads.

It is used as the base operating system for all nodes in the homelab.

Talos is purpose built for running kubernetes on bare metal. It is designed to be managed via a declarative API (`talosctl`), contains all the required packages for running kubernetes. It is also very easy to install and configure, and has a great community behind it.

## Kubernetes Cluster

The cluster has been configured using the Talos Linux API (via the `talosctl` CLI tool). `talosctl` is used to generate configuration files with security keys and certificates for each node. These files are stored in the `./talos` directory and used to setup the control plane node, each worker node and then to update / generate `kubectl` configurations.

As these config files contain sensitive information, they are not stored in the git repository. Instead, I have added examples with sensitive information removed.

### Cluster Setup

[Talos Linux Getting Started Guide](https://www.talos.dev/v1.9/introduction/getting-started/)

#### Requirements

- Bootable USB drive or other installation media for Talos Linux
  - [Ventoy](https://www.ventoy.net/en/index.html) is a great tool for this. Can install multiple ISO images on a single USB drive and choose which one to boot from.
  - Talos Linux ISO images can be built from source or downloaded from [Github releases](https://github.com/siderolabs/talos/releases).
- A separate machine with `talosctl` & `kubectl` installed (On the same network as the target nodes)

#### Control Plane Node Setup

1. Boot Talos on the control plane node from installation media
2. Generate configuration files from other machine with
  ```bash
    talosctl gen config <Cluster Name> https://<Node IP Address>:6443
  ```
  This will create the following files:
  - controlplane.yaml
  - worker.yaml
  - talosconfig
3. Determine disk where Talos will be installed
  ```bash
    talosctl get disks --nodes <Node IP Address> --insecure
  ```
4. Update the controlplane.yaml with the correct disk name for OS to be installed on. 
   1. *search for `/dev/sda` and replace `sda` with the correct disk name*
5. Apply the control plane config to the node
```
  talosctl apply-config --insecure -n <Node IP Address> --file controlplane.yaml
```

This will install Talos Linux on the control plane node and configure it to join the cluster. The node will reboot and start Talos Linux.

6. After the node has rebooted, you can check the status of the node with
```bash
  talosctl dashboard -n <Node IP Address> -e <Control Plane Node IP Address> --talosconfig=./talosconfig 
```

7. After the control plane node is in ready state. We can bootstrap the kubernetes cluster with
```bash
  talosctl bootstrap -n <Node IP Address> \
    -e <Control Plane Node IP Address> \
    --talosconfig=./talosconfig
```

8. After a few moments, you will be able to download your Kubernetes client configuration and get started adding worker nodes'
  The following will generate a `kubectl` configuration file or Update the existing one at `~/.kube/config`. If you want to specify a different filepath, append desired location to the command.
   ```bash
    talosctl kubeconfig -n <Node IP Address> \
      -e <Control Plane Node IP Address> \
      --talosconfig=./talosconfig 
   ```

9. You can now use `kubectl` to interact with the cluster. For example, you can check the status of the nodes with
```bash
  kubectl --context <Cluster Name> get nodes
```

#### Worker Node Setup
1. Boot Talos on the worker node from installation media
2. Determine disk where Talos will be installed
  ```bash
    talosctl get disks --nodes <Target Node IP Address> --insecure
  ```
3. Update the worker.yaml with the correct disk name for OS to be installed on. 
4. Apply the worker config to the node
```bash
  talosctl apply-config --insecure -n <Target Node IP Address> --file worker.yaml
```
This will install Talos Linux on the worker node and configure it to join the cluster. The node will reboot and start Talos Linux.

5. After the node has rebooted, you can check the status of the node with
```bash
  talosctl dashboard -n <Target Node IP Address> -e <Control Plane Node IP Address> --talosconfig=./talosconfig 
```
6. After the worker node is in ready state, you can check the status of the nodes with
```bash
  kubectl --context <Cluster Name> get nodes
```
You should see the new node in the cluster.

## GitOps

I am using ArgoCD to manage the deployment of applications and services in the cluster. The repository is structured to support GitOps workflows using [the App of Apps pattern](https://argo-cd.readthedocs.io/en/latest/operator-manual/cluster-bootstrapping/). 

This means that each application or service is deployed as a separate ArgoCD application manifest file within the `/argocd-apps` directory. With a single parent app watching for changes to the child application manifests.

Each child application is contained within its own directory, with a `kustomization.yaml` file that defines the resources to be deployed. The parent application is defined in the `argo/app_of_apps.yaml` file, which contains a list of all the child applications.

### Setup ArgoCD

1. Build the `kustomization.yaml` manifest file and pipe into kubectl apply

```
# inside /argo dir
kustomize build --enable-helm . | kubectl apply -f -
```

This will deploy the ArgoCD to the cluster and create the necessary resources. ArgoCD can be configured via the `values.yaml` file in the `argo` directory. This file contains the configuration for ArgoCD, including the admin password, server URL, and other settings.

2. After ArgoCD is deployed, you can access the ArgoCD UI by port-forwarding the service to your local machine
```bash
  kubectl port-forward svc/argocd-server -n argo 8080:443
```

3. **(Optional)** Access the ArgoCD UI open your web browser and navigate to `https://localhost:8080`.

You will be prompted to enter the admin password. The password will be initially deployed into the cluster as a secret. You will need to decode the secret to get the password.

```bash
  kubectl get secret argocd-initial-admin-secret -n argo -o jsonpath='{.data.password}' | base64 --decode; echo
```

4. Deploy App of Apps to ArgoCD & Sync child applications
```bash
  argocd app create apps \
    --dest-namespace argo \
    --dest-server https://kubernetes.default.svc \
    --repo git@github.com:NickMoignard/homelab.git \
    --path argocd-apps;

  # Sync parent application
  argocd app sync apps;

  # Sync child applications
  argocd app sync -l app.kubernetes.io/instance=apps;
```

Now to deploy any new applications or make changes to existing applications, you can simply update the `kustomization.yaml` file in the appropriate directory and ArgoCD will automatically detect the changes and deploy them to the cluster.

