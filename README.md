# yabe-windows

Ansible configuration for the Yabe range Windows team.

## Machines

| Hostname  | IP            | OS                    | Role                        |
|-----------|---------------|-----------------------|-----------------------------|
| dc01      | 10.30.20.10   | Windows Server 2016   | Primary DC, AD, DNS, Kerberos |
| dc02      | 10.30.20.11   | Windows Server 2025   | Secondary DC, DHCP          |
| fs01-win  | 10.30.20.12   | Windows Server 2019   | SMB, DFS Namespace          |
| app01     | 10.30.20.13   | Windows Server 2022   | IIS, intranet.yabe.corp     |

dc01 is temporarily at `192.168.10.188` in `inventory/hosts.yml`.
Hosts are grouped as `domain_controllers` (dc01, dc02) and
`member_servers` (fs01-win, app01).

## Current state

No roles exist yet. `site.yml` runs one play against every host with
`roles: []`, so a run only connects and gathers facts. That makes it a
good check that WinRM and secrets work before any roles are added.

## Setup

You need these on the machine you run Ansible from:
- Ansible and `pywinrm` (`pip install pywinrm`), which Ansible uses to talk WinRM
- `sops` and `age`
- your age private key in `~/.config/sops/age/keys.txt` (or `SOPS_AGE_KEY_FILE` pointing to it)
- your age public key listed in `.sops.yaml`, and the secrets file re-encrypted
  for it by a teammate who already has access
  (`sops updatekeys inventory/group_vars/all/secrets.sops.yml`)

Then, from the repo root:

    # Install collections (re-run when requirements.yml changes; add --upgrade to update)
    ansible-galaxy collection install -r requirements.yml

    # Get inventory/group_vars/all/secrets.sops.yml from a teammate (it is gitignored),
    # or create it: copy the template, fill in real values, then encrypt it in place
    # (sops older than 3.9 uses: sops -e -i <file>)
    cp vars/secrets.sops.yml.example inventory/group_vars/all/secrets.sops.yml
    sops encrypt -i inventory/group_vars/all/secrets.sops.yml

    # Test the connection
    ansible all -m ansible.windows.win_ping

    # Dry run
    ansible-playbook site.yml --check --diff

    # Apply (add --limit <host> for one machine)
    ansible-playbook site.yml

## How secrets are loaded

There is no `sops` wrapper around the commands. Ansible automatically loads
every file in `inventory/group_vars/all/` for every host. Plain files are read
by Ansible's built-in `host_group_vars` plugin; `secrets.sops.yml` is decrypted
in memory by the `community.sops` vars plugin (both enabled in `ansible.cfg`),
which runs `sops` with your age key. The plaintext is never written to disk.

The secrets file holds the local admin login Ansible uses
(`ansible_user`, `ansible_password`). Domain accounts will be added later
for tasks such as promoting dc02.

If decryption fails (no key, key not listed in the file, `sops` not installed),
Ansible stops with an error naming the secrets file before it connects to any
host.

View or change the secrets with:

    sops edit inventory/group_vars/all/secrets.sops.yml

**Had the secrets file in `vars/` before?** It is gitignored, so `git pull`
doesn't move it. Move your copy once:

    mv vars/secrets.sops.yml inventory/group_vars/all/secrets.sops.yml

## Structure

    site.yml                                   <- entry point (no roles yet)
    ansible.cfg                                <- ansible settings (inventory path, vars plugins)
    requirements.yml                           <- collections to install
    .sops.yaml                                 <- age public keys SOPS encrypts for
    inventory/hosts.yml                        <- target machines and groups
    inventory/group_vars/all/main.yml          <- non-secret variables for every host (domain, WinRM settings)
    inventory/group_vars/all/secrets.sops.yml  <- SOPS-encrypted secrets (gitignored, shared out of band)
    vars/secrets.sops.yml.example              <- secrets template (committed)

Roles will go in `roles/` (set as `roles_path` in `ansible.cfg`) once they
are written.

## Known issues

**WinRM "Bad HTTP response returned from server. Code 400"**, often together
with the warning "Failed to cleanup running WinRM command". This is a known
limitation of NTLM over plain HTTP (port 5985): pywinrm encrypts each message
with keys tied to the TCP connection it authenticated on. If that connection
drops mid-run, the next message goes out on a new connection, WinRM can't
decrypt it and answers 400, and every later task on that host fails the same
way. Re-run the failed host:

    ansible-playbook site.yml --limit <host>

Permanent fix: WinRM over HTTPS (port 5986), or Kerberos once hosts are
domain-joined.

## Reference

- Planning document: yabe-range-planning-document.md (not in this repo)
- Ansible docs: https://docs.ansible.com
