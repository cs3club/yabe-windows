# yabe-windows

Ansible configuration for the Yabe range Windows team.

## Machines

| Hostname  | IP            | OS                    | Role                        |
|-----------|---------------|-----------------------|-----------------------------|
| dc01      | 10.30.20.10   | Windows Server 2016   | Primary DC, AD, DNS, Kerberos |
| dc02      | 10.30.20.11   | Windows Server 2025   | Secondary DC, DHCP          |
| fs01-win  | 10.30.20.12   | Windows Server 2019   | SMB, DFS Namespace          |
| app01     | 10.30.20.13   | Windows Server 2022   | IIS, intranet.yabe.corp     |

## Setup

    # Install collections
    ansible-galaxy collection install -r requirements.yml

    # Copy secrets template and fill in real values
    cp vars/secrets.yml.example vars/secrets.yml

    # Dry run
    ansible-playbook site.yml --check --diff

    # Apply
    ansible-playbook site.yml

## Structure

    inventory/hosts.yml        <- target machines
    roles/                     <- one subdirectory per role
    vars/main.yml              <- non-secret variables
    vars/secrets.yml           <- secrets (never committed)
    vars/secrets.yml.example   <- secrets template (committed)
    site.yml                   <- entry point
    ansible.cfg                <- ansible settings

## Reference

- Planning document: yabe-range-planning-document.md
- Ansible docs: https://docs.ansible.com
