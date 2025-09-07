## :pushpin: Getting Started

This is the README file/page for Nanyang Technological University (NTU) Skillsfuture Career Transition Programme (SCTP) Cloud Infrastructure Engineering Cohort 10 (CE10) Group 3 Site Reliability Engineering (SRE) Project repository.

### :hammer_and_wrench: Prerequisites

Before you begin, ensure you have met the following requirements:

* You have installed the latest version of [Docker](https://www.docker.com/get-started).

* You have a Windows/Linux/Mac machine.

* You have basic knowledge of [Docker](https://www.docker.com/get-started).

1. Install WSL into WSL Windows Environment using the following :

    https://learn.microsoft.com/en-us/windows/wsl/install

    WSL allows us to run the Linux operating system on Windows machines. We do this because most programming uses Unix-based operating systems, of which MacOS is a descendant. Most SWEs that use Windows do their work in WSL to maximise compatibility between their work and work done on Linux machines. Before installing WSL, update Windows to the latest version.

    a. Install WSL here.
    
    b. Install the latest version of Ubuntu here. Ubuntu is a popular version of the Linux operating system.
    
    c. Run sudo apt install build-essential in Ubuntu in WSL to install standard libraries Ubuntu needs to further install common packages.
    
    d. Run sudo apt-get install ca-certificates in Ubuntu in WSL to get SSL verification certificates on Ubuntu for Ubuntu to communicate with VS Code on our computer.


2. Install Git into WSL Windows Environment using the following :

    https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-git
    
    sudo apt-get update
    sudo apt-get install git
    git –version

    git config --global user.name "<YOUR_GITHUB_USERNAME>"
    git config --global user.email "<YOUR_GITHUB_EMAIL>"

    git config --global credential.helper store
    git config --global credential.helper cache


3. Install AWS CLI into WSL Windows Environment using the following :

    https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

    After installing AWS CLI into WSL.
    https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html#sso-configure-profile-manual

    https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html#sso-configure-profile-auto


4. Install Terraform CLI into WSL Windows Environment using the following :

    https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli

    https://dev.to/aws-builders/connecting-aws-with-terraform-a-short-guide-4bda

    Create a Terraform Configuration File :
    aws configure

    It will prompt you for the following :
    AWS Access Key ID       (Enter Access Key ID)
    AWS Secret Access Key   (Enter Access Key)
    Default Region Name     (Enter region name)
    Default Output Format   (Leave as default as JSON)


### :rocket: Installing NTU SCTP CE10 SRE Project

To install NTU SCTP CE10 SRE Project, follow these steps:

1. Clone the repository:

   ```bash
   git clone
   git clone https://github.com/growfatlikeme/capstone_private.git
