## :pushpin: Getting Started

This is the README file/page for Nanyang Technological University (NTU) Skillsfuture Career Transition Programme (SCTP) Cloud Infrastructure Engineering Cohort 10 (CE10) Group 3 Site Reliability Engineering (SRE) Project repository.

## :hammer_and_wrench: Prerequisites

Before you begin, ensure you have met the following requirements:

1. Install WSL into WSL Windows Environment using the following :

    https://learn.microsoft.com/en-us/windows/wsl/install

    WSL allows us to run the Linux operating system on Windows machines. We do this because most programming uses Unix-based operating systems, of which MacOS is a descendant. Most SWEs that use Windows do their work in WSL to maximise compatibility between their work and work done on Linux machines. Before installing WSL, update Windows to the latest version.

    a. Install WSL here.
    
    b. Install the latest version of Ubuntu here. Ubuntu is a popular version of the Linux operating system.
    
    c. Run sudo apt install build-essential in Ubuntu in WSL to install standard libraries Ubuntu needs to further install common packages.
    
    d. Run sudo apt-get install ca-certificates in Ubuntu in WSL to get SSL verification certificates on Ubuntu for Ubuntu to communicate with VS Code on our computer.<br /><br />


2. Install Git into WSL Windows Environment using the following :

    https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-git
    
    sudo apt-get update<br />
    sudo apt-get install git<br />
    git –-version<br />

    git config --global user.name ''YOUR_GITHUB_USERNAME''<br />
    git config --global user.email ''YOUR_GITHUB_EMAIL''<br />

    git config --global credential.helper store<br />
    git config --global credential.helper cache<br /><br />


3. Install AWS CLI into WSL Windows Environment using the following :

    https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

    After installing AWS CLI into WSL.<br />
    https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html#sso-configure-profile-manual

    https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html#sso-configure-profile-auto<br /><br />


4. Install Terraform CLI into WSL Windows Environment using the following :

    https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli

    https://dev.to/aws-builders/connecting-aws-with-terraform-a-short-guide-4bda

    Create a Terraform Configuration File :
    aws configure

    It will prompt you for the following :<br /><br />
    AWS Access Key ID       (Enter Access Key ID)<br />
    AWS Secret Access Key   (Enter Access Key)<br />
    Default Region Name     (Enter region name)<br />
    Default Output Format   (Leave as default as JSON)<br /><br />


## :rocket: Installing & Deploying NTU SCTP CE10 SRE Project

To install NTU SCTP CE10 SRE Project, follow these steps:

1. Clone the repository:

   a. Make a new directory of your choice to clone the repository.
   
   b. Change to this newly created directory of your choice, and perform the following commands to initialize and clone the repository.

   git init<br />
   git clone https://github.com/growfatlikeme/capstone_private.git<br /><br />


2. Setup Terraform Infrastructure & Amazon Elastic Kubernetes Service (EKS) Cluster using Github Actions of the Github repository.

    ![Alt text] (images/01_Github Actions Top Menu.jpg)
   
   Click on **"OIDC Terraform setup"** to run the workflow to setup the Terraform infrastructure.

    ![Alt text] (images/02_GitHub Action Choice of Menu.jpg)

    It will take about 15 - 25 minutes to bring up the network infrastructure. Be patience.<br />

    Workflow status will prompt you the successful completion of the Terraform setup.<br /><br />


3. Deployment of Helm

   Click on **"Deploy Helm"** to run the workflow to deploy all the helm charts of the required resources/components.

    ![Alt text] (images/02_GitHub Action Choice of Menu.jpg)

   It will take about 15 - 25 minutes to complete the helm deployment. Be patience too.<br />

   Workflow status will prompt you the successful completion of the Helm deployment.<br /><br />


## :construction_worker: Tearing Down of Whole AWS EKS Cluster & Setup

Click on **"OIDC Terraform Teardown"** to run the workflow to deploy all the helm charts of the required resources/components.

  ![Alt text] (images/02_GitHub Action Choice of Menu.jpg)

It will take about 20 minutes to complete the tearing down of the whole cluster and deployment. Be patience again too.<br />

Workflow status will prompt you the successful completion of the Helm deployment.<br /><br />


## :bookmark_tabs: GitBook

This GitBook contains the documentation of CE10 Group 3 SRE capstone project. It consists of 3 main sections, namely Deployment, Application, and Site Reliability Engineering (SRE).

Below are the links to our capstone project documentation.<br />

1. **Main Capstone Project Documentation**

   [Introduction | Snake Game Docs](https://snake-game.gitbook.io/snake-game-docs/documentation)

   
2. **Deployment**

   [Helm](https://snake-game.gitbook.io/snake-game-docs/documentation/deployment/helm)

   [GitHub Workflows](https://snake-game.gitbook.io/snake-game-docs/documentation/deployment/github-workflows)

   [Setup Architecture](https://snake-game.gitbook.io/snake-game-docs/documentation/deployment/readme)

3. **Application**

   [Snake Game](https://snake-game.gitbook.io/snake-game-docs/documentation/application/readme)

   [Deployment](https://snake-game.gitbook.io/snake-game-docs/documentation/application/deployment)

   [Infrastructure](https://snake-game.gitbook.io/snake-game-docs/documentation/application/infrastructure)
    

4. **Site Reliability Engineering (SRE)**

   [Status Pages](https://snake-game.gitbook.io/snake-game-docs/documentation/site-reliability-engineering/readme)

   [Load Testing](https://snake-game.gitbook.io/snake-game-docs/documentation/site-reliability-engineering/load-testing)

   [Monitoring](https://snake-game.gitbook.io/snake-game-docs/documentation/site-reliability-engineering/monitoring)
