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
    cp vars/secrets.sops.yml.example inventory/group_vars/all/secrets.sops.yml
    sops encrypt -i inventory/group_vars/all/secrets.sops.yml

    # Test the connection
    ansible all -m ansible.windows.win_ping

    # Dry run
    ansible-playbook site.yml --check --diff

    # Apply (add --limit <host> for one machine, --tags <tag> for one area)
    ansible-playbook site.yml

## How secrets are loaded

There is no `sops` wrapper around the commands. Ansible automatically loads
every file in `inventory/group_vars/all/` for every host. Plain files are read
by Ansible's built-in `host_group_vars` plugin; `secrets.sops.yml` is decrypted
in memory by the `community.sops` vars plugin (both enabled in `ansible.cfg`),
which runs `sops` with your age key. The plaintext is never written to disk.

If decryption fails (no key, key not listed in the file, `sops` not installed),
Ansible stops with an error naming the secrets file before it connects to any
host.

View or change the secrets with:

    sops edit inventory/group_vars/all/secrets.sops.yml

## Structure

    site.yml                                   <- entry point
    ansible.cfg                                <- ansible settings (inventory path, vars plugins)
    requirements.yml                           <- collections to install
    .sops.yaml                                 <- age public keys SOPS encrypts for
    inventory/hosts.yml                        <- target machines and groups
    inventory/group_vars/all/main.yml          <- non-secret variables for every host
    inventory/group_vars/all/secrets.sops.yml  <- SOPS-encrypted secrets (gitignored, shared out of band)
    vars/secrets.sops.yml.example              <- secrets template (committed)
    roles/                                     <- one subdirectory per role
    roles/common/                              <- baseline hardening for every host

### Tags

Run part of the playbook with `--tags`, or leave part out with `--skip-tags`.
Combine tags with commas (`--tags protocols,logging`). To see the tags or
preview which tasks a tag selects, without running anything:

    ansible-playbook site.yml --list-tags
    ansible-playbook site.yml --list-tasks --tags firewall

| Tag           | What it does                                                                                       | Reboot needed? |
|---------------|----------------------------------------------------------------------------------------------------|----------------|
| `common`      | The whole common (baseline) role: every tag below                                                  | see below      |
| `protocols`   | Disables SMBv1, LLMNR/mDNS, NetBIOS broadcasts, LM/NTLMv1; requires SMB signing; blocks anonymous enumeration | for SMBv1 and SMB signing |
| `credentials` | Disables WDigest, turns on LSA protection (RunAsPPL), keeps UAC on without breaking Ansible's login | for LSA protection |
| `accounts`    | Disables Guest and reversible password storage; local password and lockout policy (skipped on promoted DCs) | no |
| `services`    | Stops and disables the Print Spooler; requires NLA and TLS for RDP                                 | no             |
| `defender`    | Makes sure Defender is installed and can't be switched off; reports any exclusions                 | if Defender had to be installed |
| `logging`     | Advanced audit policy, command lines in process events, PowerShell script block logging, bigger event logs | no |
| `firewall`    | Allow rules for WinRM and each host's services, then firewall on with inbound blocked. Dry run first: `--tags firewall --limit <host> --check --diff` | no |

Reboots never happen automatically; the run ends with a reminder instead.
Add `-e common_allow_reboot=true` to let Ansible reboot (use `--limit` so
only one DC goes down at a time).

## Known issues

**WinRM "Bad HTTP response returned from server. Code 400"**, often together
with the warning "Failed to cleanup running WinRM command". This is a known
limitation of NTLM over plain HTTP (port 5985): pywinrm encrypts each message
with keys tied to the TCP connection it authenticated on. If that connection
drops mid-run, the next message goes out on a new connection, WinRM can't
decrypt it and answers 400, and every later task on that host fails the same
way. The tasks themselves are fine. Re-run the failed host/tag; the roles are
idempotent, so only the unfinished work is applied:

    ansible-playbook site.yml --limit <host> --tags <tag>

Permanent fix: WinRM over HTTPS (port 5986), or Kerberos once hosts are
domain-joined.

## Reference

- Planning document: yabe-range-planning-document.md
- Ansible docs: https://docs.ansible.com
