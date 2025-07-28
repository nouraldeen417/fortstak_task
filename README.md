
# 📝 To-Do List App — Full CI/CD Deployment with Docker, Ansible, Terraform, and Argo CD

This project is a Node.js + MongoDB To-Do List application built as a containerized microservice.  
I implemented a full DevOps workflow starting from Dockerization, automated image building with GitHub Actions, provisioning infrastructure using Terraform, and deploying with Ansible.  
The app was deployed in two environments:  
- On AWS using Docker Compose  
- On-premises Kubernetes cluster using Argo CD  

The image is stored in a **private GitHub Container Registry (GHCR)**.  
Auto-updating mechanisms were implemented using **Watchtower** (for Docker) and **Argo CD Image Updater** (for Kubernetes).  
All infrastructure provisioning, configuration, and deployments were automated end-to-end.  
All credentials were handled securely.  
This README documents everything I built and configured for this deployment task.

---

## 📘 Table of Contents

1. [Dockerfile](#1-dockerfile)  
2. [GitHub Actions for CI](#2-github-actions-for-ci)  
3. [Ansible for Environment Preparation & Deployment](#3-ansible-for-environment-preparation--deployment)  
4. [Terraform for AWS EC2 Setup](#4-terraform-for-aws-ec2-setup)  
5. [Docker Compose & Watchtower](#5-docker-compose--watchtower)  
6. [Kubernetes Manifests](#6-kubernetes-manifests)  
7. [Argo CD & Image Updater](#7-argo-cd--image-updater)

---

## 1. Dockerfile

I wrote a simple and efficient `Dockerfile` to containerize the Node.js To-Do List application. I used the `node:18-alpine` base image to keep the final image as small  as possible. The working directory was set to `/app`, and only the necessary files were copied in logical steps to improve layer caching.

The image installs all dependencies listed in `package.json`, copies the full project, exposes port **4000** (used by the backend server), and finally starts the app using the `npm start` command.

This is the Dockerfile used:

```Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 4000
CMD ["npm", "start"]

```

All configuration values (such as port and start script) were inherited directly from the developer’s original project repository.


---

## 2. GitHub Actions for CI

To automate the build and push process, I used **GitHub Actions** to create a CI pipeline triggered only when changes are made to the `src/` directory on the `main` branch. This ensures that changes to unrelated parts of the repository (like the `README.md` or infrastructure code) don’t trigger unnecessary builds.

The job runs on **`ubuntu-latest`**, taking advantage of GitHub's hosted runners for speed and simplicity. I used the **GitHub Container Registry (GHCR)** instead of a self-hosted private registry. This choice reduced complexity, avoided authentication issues, and integrated seamlessly with GitHub Actions.

The workflow defines minimal permissions (`contents: read`, `packages: write`) to allow pushing images to GHCR securely. I used the built-in `GITHUB_TOKEN` and `${{ github.actor }}` to authenticate the push without exposing secrets.

Here’s the exact GitHub Actions workflow file I used:

```yaml
name: CI - Build & Push to GHCR

on:
  push:
    branches: [ "main" ]
    paths:
      - 'src/**'

jobs:
  build-and-push:
    runs-on: ubuntu-latest

    permissions:
      contents: read
      packages: write # Required to push to GHCR

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Log in to GHCR
      run: echo "${{ secrets.GITHUB_TOKEN }}" | docker login ghcr.io -u ${{ github.actor }} --password-stdin

    - name: Build Docker image
      run: |
        cd src/
        docker build -t ghcr.io/${{ github.repository_owner }}/my-node-app:latest .

    - name: Push Docker image
      run: |
        docker push ghcr.io/${{ github.repository_owner }}/my-node-app:latest

```

This setup automatically builds and pushes the `app:latest` Docker image to your private GHCR , every time the application code is updated.

---

## 3. Ansible for Environment Preparation & Deployment

To automate environment preparation and application deployment, I created a modular **Ansible setup** using a main playbook (`site.yml`) and reusable roles. The structure was designed to support multiple operating systems (Debian/Ubuntu and RHEL/CentOS), allow secure authentication with a private registry, and manage both cloud and on-prem hosts.

### 🔧 Purpose of Each Role

- **`docker_install`**: Installs Docker on the target system. It supports both **Debian-based** and **RedHat-based** distributions by using OS-specific variable files (e.g. `roles/docker_install/vars/main.yaml`).
  
- **`docker_registry_setup`**: Logs into the private **GHCR** registry using credentials stored in an encrypted `vault.yml` file. This approach ensures sensitive information (like tokens) is not hardcoded or pushed to the repo.

- **`docker_compose`**: Copies a predefined `docker-compose.yml` file to the remote host (stored in `roles/docker_compose/files/`) and runs it to deploy the app and MongoDB services.

### 🗂️ Ansible Directory Structure


```

ansible/  
├── site.yml  
├── vault.yml  
├── inventory/  
│ ├── aws_hosts # auto-generated after Terraform run  
│ └── on_prem_hosts # manually maintained  
└── roles/  
| ├── docker_install/  
| ├── docker_registry_setup/  
| └── docker_compose/

```

This setup supports **manual or scripted host inventory updates**. For example, after running Terraform, a script places the EC2 public IP into `inventory/aws_hosts`, allowing Ansible to target it immediately.

### 📄 site.yml (Main Playbook)

```yaml
- name: Apply selected roles
  hosts: all
  become: yes
  become_method: sudo
  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=accept-new'  # Accept new SSH keys automatically
  vars_files:
    - vault.yml  # Load sensitive variables from vault

  roles:
    - role: docker_install            # Install Docker (OS-specific)
    - role: docker_registry_setup     # Login to GHCR using vault credentials
    - role: docker_compose            # Deploy using Docker Compose

```

This design ensures that the Ansible setup is **flexible**, **secure**, and **reusable across different environments** and projects.

---

## 4. Terraform for AWS EC2 Setup

 I added **Terraform** to automate infrastructure provisioning as an additional improvement. The design provisions a minimal yet complete AWS setup to host the To-Do List app in a cloud environment.

### 🏗️ Infrastructure Design

- **1 EC2 instance** running Ubuntu (used as the deployment target)
- **1 VPC** with:
  - **2 public subnets**
  - **Internet Gateway**
  - All required routing and security configurations
- **Security Groups** to allow SSH (port 22) and app traffic (port 80)

### 🔑 Integration with Ansible

After provisioning, a local **helper script** automatically:
- Extracts the EC2 public IP
- Creates a host entry in `ansible/inventory/aws_hosts`
- Stores the SSH private key locally (used later during Ansible execution)

### ☁️ State Management

To persist the Terraform state securely and support future updates, I configured **remote state storage in an S3 bucket on AWS**.

This Terraform setup made the deployment process more consistent, repeatable, and cloud-ready.

---

## 5. Docker Compose & Watchtower


To deploy the application on AWS EC2, I used **Docker Compose** with three services:

- **`app`** – The Node.js To-Do List application
- **`mongo`** – MongoDB as the database
- **`watchtower`** – For automatically monitoring and updating the `app` container when a new image is pushed to GHCR

Here’s the full `docker-compose.yml` file I used:

```yaml
version: "3.9"
services:
  app:
    image: ghcr.io/nouraldeen417/my-node-app:latest
    ports:
      - "80:4000"
    depends_on:
      - mongo
    environment:
      - MONGO_URI=mongodb+srv://ankitvis609:Sonu135790@cluster0.esi3ulq.mongodb.net/todolistDb
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    healthcheck:
      test:  ["CMD", "wget", "-q", "--spider", "http://localhost:4000"]
      interval: 30s
      timeout: 10s
      retries: 3

  mongo:
    image: mongo:7
    volumes:
      - mongo-data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.runCommand('ping')"]
      interval: 30s
      timeout: 10s
      retries: 5

  watchtower:
    image: containrrr/watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ~/.docker/config.json:/config.json
    command: --label-enable --cleanup --interval 30
    restart: always

volumes:
  mongo-data:

```
> 🔐 **Hint:** The volume `~/.docker/config.json:/config.json` allows Watchtower to access Docker Hub or GitHub Container Registry (GHCR) credentials.  
> After the Ansible script sets up the registry login on the EC2 machine using `docker login`, this file contains the auth tokens required to pull private images — making Watchtower fully compatible with private registries.

### ✅ Health Checks

I added health checks for both the application and MongoDB to ensure reliability:

-   **App**: Uses `wget` to check if the Node.js server is responding on port 4000.
    
-   **MongoDB**: Executes a simple `db.runCommand('ping')` to verify database readiness.
    

This improves container orchestration and ensures that Docker Compose waits for services to be healthy before continuing.

### 🚀 Why Watchtower is the Best Fit Here

**Watchtower** is the perfect lightweight solution to handle automatic image updates in this setup because:

-   It continuously checks the registry (GHCR) for new versions of tagged images (`latest`)
    
-   It only updates containers that are explicitly labeled (safe and scoped)
    
-   It **cleans up** old images automatically to save disk space
    
-   It works **without needing a full CI/CD tool** or extra pipelines on the EC2 instance
    
-   It fits perfectly with GitHub Actions, where the image is built and pushed — then Watchtower picks up the change and redeploys seamlessly
    

This gives me a **minimal but effective continuous delivery pipeline** without additional complexity.


---

## 6. Kubernetes Manifests

### 🧩 **1. Todo App Deployment and Service**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: todoapp
  name: todo-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: todoapp
  template:
    metadata:
      labels:
        app: todoapp
    spec:
      containers:
      - image: ghcr.io/nouraldeen417/my-node-app:latest  # Pull from private registry
        name: todoapp
        ports:
        - containerPort: 4000
        envFrom:
        - configMapRef:
            name: mongodb-config  # Inject MongoDB URL from config map
      imagePullSecrets:
      - name: ghcr-secret  # Secret used to authenticate with GHCR private registry

```

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: todoapp-svc
spec:
  selector:
    app: todoapp
  type: NodePort  # Expose service on Node IP at a static port
  ports:
  - port: 4000
    targetPort: 4000
    nodePort: 30007  # Custom port to access app externally (e.g., http://nodeIP:30007)

```

📝 **Notes:**

-   This deployment exposes a containerized Node.js app on port `4000`.
    
-   Uses a `NodePort` to make the app accessible externally .
    
-   Uses `envFrom` to get the Mongo URI from a ConfigMap.
    
-   The `imagePullSecrets` is necessary to pull the image from a **private registry** like GHCR.
    

----------

### 📦 **2. MongoDB Deployment and Service**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mongodb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongodb
        image: mongo:7
        ports:
        - containerPort: 27017
        volumeMounts:
        - name: mongodb-data
          mountPath: /data/db
      volumes:
      - name: mongodb-data
        emptyDir: {}  

```

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: mongodb-service
spec:
  selector:
    app: mongodb
  ports:
    - protocol: TCP
      port: 27017
      targetPort: 27017

```


----------

### 🔐 **Why `imagePullSecrets` is Important**

Your application image is hosted on a **private registry (GHCR)**. To allow the Kubernetes node to pull the image securely, you create a secret using:

```bash
kubectl create secret docker-registry ghcr-secret \
  --docker-username=your-username \
  --docker-password=your-ghcr-token \
  --docker-server=ghcr.io \
  --namespace=default

```

Then you reference it under `imagePullSecrets` in the pod spec — this ensures the image pull will **not fail due to authentication**.
---

## 7. Argo CD & Image Updater


### 🛠️ Continuous Deployment with Argo CD and Image Updater

To enable **automated deployments** and **image updates** in Kubernetes, I used [**Argo CD**](https://argo-cd.readthedocs.io/en/stable/) along with [**Argo CD Image Updater**](https://argocd-image-updater.readthedocs.io/en/stable/).

----------

### ✅ Deployment Steps

1.  **Install Argo CD and Image Updater**  
    I deployed both using official manifests provided in the documentation:
    
    ```bash
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/main/manifests/install.yaml
    
    ```
    
2.  **Argo CD Application for My App**  
    I created an Argo CD `Application` resource that points to my GitHub repo, specifically the `k8s/` folder (to avoid syncing unrelated files).
    
    ```yaml
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: argo-app
      namespace: argocd
      annotations:
        argocd-image-updater.argoproj.io/image-list: my-app=ghcr.io/nouraldeen417/my-node-app:latest
        argocd-image-updater.argoproj.io/my-app.update-strategy: digest
    spec:
      project: default
      source:
        repoURL: https://github.com/nouraldeen417/fortstak_task
        targetRevision: HEAD
        path: k8s
      destination:
        server: https://kubernetes.default.svc
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
    
    ```
    
    -   🔄 **Annotations**: These tell Argo CD Image Updater which image to monitor and use digest-based updates to avoid `latest` tag caching issues.
        
    -   ✅ **Auto Sync**: Ensures that when a new image is pushed, the app redeploys automatically with the updated image.
        
3.  **ConfigMap for Image Updater**  
    To enable pulling from my **private GHCR registry**, I used the following `ConfigMap`:
    
    ```yaml
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: argocd-image-updater-config
      namespace: argocd
    data:
      registries.conf: |
        registries:
          - name: GitHub Container Registry
            prefix: ghcr.io
            api_url: https://ghcr.io/
            credentials: pullsecret:argocd/ghcr-secret
    
    ```
    
4.  **Secret for Private Registry**  
    I created a Kubernetes secret with GHCR credentials in the `argocd` namespace:
    
    ```bash
    kubectl create secret docker-registry ghcr-secret \
      --docker-username=<username> \
      --docker-password=<token> \
      --docker-server=ghcr.io \
      -n argocd
    
    ```
    
5.  **Verify Everything is Working**
    
    -   ✅ Visited the Argo CD Web UI to ensure sync status is `Synced` and `Healthy`.
        
    -   🔍 Checked logs from the `argocd-image-updater` pod using:
        
        ```bash
        kubectl logs deployment/argocd-image-updater -n argocd
        
        ```
        
    -   🔁 Verified that the pod correctly detects image updates and applies them to the deployment.
        

---

## 📎 Author

- 🧑‍💻Nour Aldeen Nabil
- 📫 Contact: nouraldeennabil259@gmail.com

---

