# 1) 
## a) Build the application locally and create a docker image.
###	i) Write the Commands for publishing the image to ACR from local environment.
		Need to have Azure account, then download Azure CLI and login into CLI with 
			$ az login
		Tag the Docker image for ACR
			$ docker tag <docker-image-name> <acr-name>.azurecr.io/<docker-image-name>
****
Docker images must be tagged with the registry's domain name (e.g., <acr-name>.azurecr.io) to indicate where the image will be stored.
This tells Docker:
    Registry: The image belongs to <acr-name>.azurecr.io.
    Repository: The image is stored in the myapp repository.
    Version: The version of the image is 1.0.
****
		
		Authenticate to ACR
		 Use the Azure CLI to authenticate with ACR:
			$ az acr login --name <acr-name>
		Push the Docker Image to ACR
			$ docker push <acr-name>.azurecr.io/<docker-image-name>

		** To List ACR repositories (images pushed)
			$ az acr repository list --name <acr-name> --output table
			Now we have image in repository of ACR, we can pull the image then if we run the command 
				docker run -p 3000:3000 <acr-name>.azurecr.io/<docker-image-name> 
			then we can see the nodejs app running on http://localhost:3000

###	ii) Provide the direction to admin team for making the ACR highly available
		To make our registry highly available:
			Enable Geo-location(availability and reduce latency for regional operations):
				*)Configure Geo-Replication for ACR to replicate container images across multiple Azure regions.
				   $ az acr replication create --registry <acr-name> --location <secondary-region>
				*)Azure Container Registry supports optional zone redundancy which provides resiliency and high 
				  availability to a registry or replication resource (replica) in a specific region.

	 
## b) Design & Configure the AKS environment along with below criteria’s
### i) Configure the AKS vnet and describe the other networking criterias considered.
Create a dedicated VNet for the AKS cluster and its associated components.

    VNet Creation:
        Create a VNet with sufficient address space (e.g., 10.0.0.0/16).
        Divide the address space into subnets for specific components:
            AKS Subnet: 10.0.0.0/22 for AKS nodes.
            Pod Subnet: 10.0.4.0/22 for Pods if using Kubenet or Azure CNI.
            Other Subnets: Reserve subnets for additional resources like Azure Application Gateway, database services, and Key Vault.

    Subnet Configurations:
        Ensure subnets do not overlap with any existing VNets connected via VNet peering.
        Enable Service Endpoints for Azure services like Key Vault, Azure SQL Database, and Azure Storage.
`aks-vnet.tf`

networking criterias
a. Network Security
    Network Security Groups (NSGs):
        Apply NSGs to the AKS subnet to restrict incoming/outgoing traffic.
        Rules:
            Allow internal traffic between AKS, Pod subnet, and Azure services.
            Allow only required external traffic (e.g., port 80/443 for web apps).

    Private Cluster:
        Configure AKS as a private cluster to disable public API server access.
        Enable access to the API server using an Azure Bastion host or an Azure Virtual Machine within the same VNet.

### ii) Design for use of Roles and authorization for users.
Azure Active Directory to enforce Identity based access.
In our AKS creation we can enable Azure AD integration to bind the cluster to an Azure AD tenant.
Create Users/groups for different roles like `admin` , `dev` or even fine grained control with "Application Permissions" and "Conditional Access policies" which will allow us to restrict user access to only a specific application or service.



## c) Design the use of any Azure DB SaaS service e.g. PostGresDB service etc. for your application in AKS cluster
### i) Key Architectural Directions for Azure Admin Team to Create DB Services
 
guide for Azure Admin Team to create a robust, scalable, and secure database service:

** Selection of Database Service

    Let's use PostgreSQL Server for its scalability, high availability, and built-in support for features like point-in-time restore.
    Enable zone redundancy for high availability if the application is deployed across multiple availability zones.

** Networking Configuration

    Use private endpoints to restrict access to the database, ensuring that it is accessible only within the Azure Virtual Network (VNet) connected to the AKS cluster.
    Integrate the PostgreSQL service with a subnet in the same VNet as the AKS cluster to ensure low-latency connectivity.
    Configure Network Security Groups (NSGs) on the subnet to allow only AKS-related IP ranges.

** Backup and Recovery

    Enable automatic backups with a sufficient retention period (e.g., 7–30 days) depending on recovery point objectives (RPO).
    Test point-in-time restore capabilities to ensure data recovery readiness.

** Scaling

    Enable autoscaling for the database service, which adjusts the compute resources based on workload requirements.
    Monitor and adjust the connection limits and query throughput settings to avoid bottlenecks.

** Monitoring and Alerts

    Set up monitoring via Azure Monitor and configure alerts for key metrics like CPU utilization, connection usage, and slow queries.
    Enable query performance insights to detect and optimize slow-running queries.

### ii) Steps for Using Azure Key Vaults for DB

To secure sensitive information such as connection strings, credentials, or keys, integrate Azure Key Vault with the AKS cluster as follows:

a. Store Database Credentials in Azure Key Vault

    Create an Azure Key Vault resource.
    Add secrets for:
        Database connection string (e.g., db-connection-string).
        Admin username (e.g., db-admin-user).
        Admin password (e.g., db-admin-pass).

b. Enable Access to Key Vault from AKS

    Assign Managed Identity to AKS:
        Enable the Managed Identity for the AKS cluster.
        Grant the AKS-managed identity access to the Key Vault by assigning the Key Vault Secrets User role.
    Network Integration:
        Ensure that the Key Vault is configured with private endpoints if the AKS cluster is using a private VNet.
        Update NSGs to allow traffic between the AKS subnet and the Key Vault.


## d) Design the key criteria for application build to be deployed in AKS cluster.
### i) steps to expose the web frontend as a load balanced service. Also, define the security around the exposed service.
We will need to ensure that web application is: 
    Accessible to end-users with high availability.
    Secure against external threats.
    Scalable to handle traffic.

Use the Kubernetes `LoadBalancer` service to expose our Web FrontEnd. It will automatically provision ALB (Azure Loadbalancer)
with public IP and distribute traffic evenly across healthy pods.
`frontend-service.yaml`

For security we will restrict inbound traffic to only HTTPS (port 443) and allow outbound traffic to only necssary services like 
our AKS nodes, databases, so that it will reduce the ttack surface.

As our web frontend sohuld also be highly available, we will do a multi-zone deployment
 * Deploy our AKS node pool across multiple availability zones so that application remains available even if one zone fails.

### ii) External INGRESS (NGINX)
We can use NGINX for ingress controller to route requests to right part of application. Have decided with NGINX so that we can
avoid vendor lockin and also NGINX has some advanced featureslike rate limiting.

### iii) Using AZURE DNS for mapping URL to our application
Assumption: We have a domain registered with any provider (ex: namecheap) and we have our application deployed on our created AKS

*) In Azure portal we can create DNS Zone
After thatwe can get the external IP from our Ingress controller NGINX and create a record in DNS Zone
    With Application Name, IP
Create alias record with using Azure DNS Alias Records type CNAME, then update resgisteres nameserver with our Azure nameserver.


### iv) Configuring SSL/TLS certi
We can use cert-manager to request and renew new certificates
Install cert-manager and create k8 resource ClusterIssuer to generate signed certificate.

```
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  ca: 
    secretName: ca-key-pair
 
```


### v) Image scanning tool 
We want to ensure that only images without any vulnerabilities should be deployed. For that we can use image scanning tools (ex: AquaSec)
during our CI/CD pipeline to scan the images for risks.

# 2) Configure monitoring for you AKs cluster using Azure Monitor or similar tool.
Azure monitor as tool:
We should monitor Cluster-level metrics, node-level metrics, container/pod metrics
Azure Monitor uses a Log Analytics agent (DaemonSet) to collect logs and metrics, ensure the agent is deployed in the kube-system namespace.

# 3) Autoscaling; horizontal pod autoscaling 
We should automatically scale the number of application pods (and cluster nodes) to handle traffic spike.
HPA : 

Dynamically adjusts the number of pod replicas based on observed metrics (e.g., CPU, memory, custom metrics).
Which will ensure application responsiveness during high traffic.
`horizontal-pod-autoscaling.yml`

Should also enable cluster autoscaler which scales AKS node pools up/down based on pod resource requests which pods
from being stuck in "Pending" state due to insufficient nodes.

We enable it during AKS cluster creation
```
az aks create --enable-cluster-autoscaler \
  --min-count 3 \
  --max-count 10 \
  -g <resource-group> -n <cluster-name>
```


# 4) Steps for Helm chart
For helm charts with specific environment creation we can have our project structure as below
       
values.yaml         
values-dev.yaml   
values-prod.yaml 

For deployment specific helm chart creation, we can generate kubernetes manifest frrom values.yaml

```
apiVersion: app/v1  
kind: Deployment  
metadata:  
  name: {{ .Release.Name }}-deployment  
spec:  
  replicas: {{ .Values.replicaCount }}  
  selector:  
    matchLabels:  
      app: {{ .Chart.Name }}  
  template:  
    metadata:  
      labels:  
        app: {{ .Chart.Name }}  
    spec:  
      containers:  
        - name: {{ .Chart.Name }}  
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"  
          imagePullPolicy: {{ .Values.image.pullPolicy }}  
          envFrom:  
            - configMapRef:  
                name: {{ .Release.Name }}-config  
            - secretRef:  
                name: {{ .Release.Name }}-secrets  
          resources:  
            {{- toYaml .Values.resources | nindent 12 }}  
```

Image Tags: Use {{ .Values.image.tag }} for environment-specific versions.
Resource Limits: Define CPU/memory in values.yaml for each environment.

# 5) Azure DevSecOps Pipeline 
## a) Design Build / CI pipeline and describe the recommended tools for each step. 
### i) Define the configuration of agent/build servers, use of agent pools.
We will need our VM as self hosted agent (B adding self hosted Agent pool)
Infrastructure:
    Azure VM with:
        OS: Ubuntu 22.04 LTS (recommended for DevOps).
        Network: Deployed in a private subnet with restricted inbound ports 
Create Personal access token for authentication from VM
This agent pool will be deployed in out VNet to securely access private ACR, Key Vault, or AKS clusters.

### ii) detailed integration steps for SonarQube
Assuming we have SonarQube Hosted instance with admin access.
Install SonarQube extesnion in Azure devops marketplace
Generate token for SonarQube, copy the token
Create a service connection in Azure Devops:
    In project settings, create a new service connection for sonarqube, add server url `http://sonarqube.companyName.com:9000`
    paste the token that we received in above step. Name the service as SonarService.
As we have self hosted build agent, we need to make sure that at least the minimum SonarQube-supported version of Java installed.

Configure the pipeline
```
trigger:
  - main

variables:
  SONAR_PROJECT_KEY: "my-react-app"
  SONAR_PROJECT_NAME: "My React App"
  SONAR_HOST_URL: "http://sonarqube.company.com:9000"

stages:
- stage: BuildAndAnalyze
  jobs:
  - job: SonarQube_Analysis
    pool:
      vmImage: "ubuntu-latest"
    steps:
    - checkout: self
      fetchDepth: 0
    - task: SonarQubePrepare@6
      inputs:
        SonarQube: "SonarQube-Service"
        scannerMode: "CLI"
        configMode: "manual"
        cliProjectKey: $(SONAR_PROJECT_KEY)
        cliProjectName: $(SONAR_PROJECT_NAME)
        cliSources: "src"  # Path to source code
        extraProperties: |
          sonar.exclusions=**/node_modules/**,**/*.test.js
          sonar.javascript.lcov.reportPaths=coverage/lcov.info
    - script: |
        npm ci
        npm run build
        npm test -- --coverage
      displayName: "Build & Test"

    #Run SonarQube analysis
    - task: SonarQubeAnalyze@6

    #Publish results to SonarQube
    - task: SonarQubePublish@6
      inputs:
        pollingTimeoutSec: "300"
```

### ii) Sonar qualitygates
We need to have qualitygates policy in out organisation so that we can know if our project is production ready.
The Sonar way quality gate has four conditions: 
    No new issues are introduced
    All new security hotspots are reviewed
    New code test coverage is greater than or equal to 80.0%

SonarQube Clean as You Code methodology
    Reliability Rating is not worse than A
    Security Rating is not worse than A
    Maintainability Rating is not worse than A


Automated Quality gates that we can enforce: 
Cognetive Complexity of code.
test coverage on code is greater than or equal to 80.0%
There is no security hotspots in code

## b) CD pipeline

### i) 
Cloud agnosstic deployment:
Use Terraform and Helm, as they are not tied to any specific cloud provider. 
Store environment-specific values in separate .tfvars files



### ii)  detailed steps to build automated Quality Gates for promoting the code from one environment to other.

Automated Quality Gates for CD Pipeline:

    Integration Tests: Run end-to-end tests using tools like Postman or Selenium.
    Health Checks: Use Kubernetes liveness and readiness probes.
    Performance Testing.

We must have multiple environments
And code will be promoted to  `Development -> Staging -> Production` 

Promoting from Development Stage -> Staging Stage 
 * Code Quality Checks: SonarQube 
 * Unit tests validation: Minimum test success rate (set as per project)
 * Dependency Scanning: Scan dependency for known vulnerabilities

Staging -> Production
* Integration testing
* Load testing/ performance testing

### iii) Manual approvals
For additional controls, manual approvals can be enforced for deployment to production
* By using `Azure DevOps Approvals and Checks` 
Add users and groups as your designated Approvers, and, if desired, provide instructions for the approvers.

* Branch control checks: ensure all the resources linked with the pipeline are built from the allowed branches and that the branches have protection enabled
 * Business hour check