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

> **These commands require SOPS.** Every run goes through `sops exec-file`,
> which decrypts `vars/secrets.sops.yml` on the fly. They will NOT work unless,
> on your machine:
> - `sops` and `age` are installed,
> - your age private key is in `~/.config/sops/age/keys.txt` (or `SOPS_AGE_KEY_FILE` points to it),
> - your age public key is listed in `.sops.yaml` and the secrets file has been
>   re-encrypted for it (`sops updatekeys vars/secrets.sops.yml`).
>
> Otherwise sops fails (e.g. "failed to get the data key") before Ansible starts.

    # Install collections
    ansible-galaxy collection install -r requirements.yml

    # Get vars/secrets.sops.yml from a teammate (it is gitignored), or create it:
    # copy the template, fill in real values, then encrypt it in place
    cp vars/secrets.sops.yml.example vars/secrets.sops.yml
    sops encrypt -i vars/secrets.sops.yml

    # Test the connection
    sops exec-file vars/secrets.sops.yml 'ansible all -m ansible.windows.win_ping -e @vars/main.yml -e @{}'

    # Dry run
    sops exec-file vars/secrets.sops.yml 'ansible-playbook site.yml -e @vars/main.yml -e @{} --check --diff'

    # Apply
    sops exec-file vars/secrets.sops.yml 'ansible-playbook site.yml -e @vars/main.yml -e @{}'

## Structure

    inventory/hosts.yml            <- target machines
    roles/                         <- one subdirectory per role
    vars/main.yml                  <- non-secret variables
    vars/secrets.sops.yml          <- SOPS-encrypted secrets (gitignored, shared out of band)
    vars/secrets.sops.yml.example  <- secrets template (committed)
    site.yml                       <- entry point
    ansible.cfg                    <- ansible settings

## Known issues

**WinRM "Bad HTTP response returned from server. Code 400"**, often together
with the warning "Failed to cleanup running WinRM command". This is a known
limitation of NTLM over plain HTTP (port 5985): pywinrm encrypts each message
with keys tied to the TCP connection it authenticated on. If that connection
drops mid-run, the next message goes out on a new connection, WinRM can't
decrypt it and answers 400, and every later task on that host fails the same
way. The tasks themselves are fine. Re-run the failed host/tag; the roles are
idempotent, so only the unfinished work is applied:

    sops exec-file vars/secrets.sops.yml 'ansible-playbook site.yml -e @vars/main.yml -e @{} --limit <host> --tags <tag>'

Permanent fix: WinRM over HTTPS (port 5986), or Kerberos once hosts are
domain-joined.

## Reference

- Planning document: yabe-range-planning-document.md
- Ansible docs: https://docs.ansible.com
