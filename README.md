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

Like the sister repo (yabe-linux), there is **one role per machine** and
`site.yml` has one play per machine, in build order.

| Role | Status | Does |
|------|--------|------|
| `dc01` | done | promotes dc01 to the first DC of `yabe.corp`, creates OUs, department groups, 30 users and the GPOs. See [roles/dc01/README.md](roles/dc01/README.md) |
| `dc02` | planned | additional DC (joins + replicates from dc01), DHCP |
| `fs01_win`, `app01` | planned | join the domain, then file shares / IIS |
| `base` | planned | anything all four machines need |

No role hardens Windows; security settings stay at their defaults.

**Promoting dc01 needs a reboot**, and Ansible never reboots unless you
allow it, so the first run stops and asks you to reboot:

    ansible-playbook site.yml --limit dc01                       # promotes, then stops
    ansible dc01 -m ansible.windows.win_reboot                   # reboot by hand
    ansible-playbook site.yml --limit dc01                       # users + GPOs

or in one run: `ansible-playbook site.yml --limit dc01 -e allow_reboot=true`.

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

The secrets file holds:

| Variable | Used for |
|----------|----------|
| `ansible_user`, `ansible_password` | the admin login Ansible uses on every host |
| `safe_mode_password` | DSRM (repair-mode) password set when a server becomes a DC |
| `ad_user_password` | starting password of all dummy users (set only at creation) |
| `domain_join_user`, `domain_join_password` | later: promoting dc02, joining member servers |

`safe_mode_password` and `ad_user_password` must meet Windows complexity
(7+ characters, 3 of upper/lower/digit/symbol). The playbook stops with a
clear message if one is missing. See `vars/secrets.sops.yml.example`.

After dc01 is promoted, `Administrator` on dc01 means the domain account
`YABE\Administrator` with the same password, so the login doesn't change.

If decryption fails (no key, key not listed in the file, `sops` not installed),
Ansible stops with an error naming the secrets file before it connects to any
host.

View or change the secrets with:

    sops edit inventory/group_vars/all/secrets.sops.yml

**Had the secrets file in `vars/` before?** It is gitignored, so `git pull`
doesn't move it. Move your copy once:

    mv vars/secrets.sops.yml inventory/group_vars/all/secrets.sops.yml

## Structure

    site.yml                                   <- entry point: one play per machine
    ansible.cfg                                <- ansible settings (inventory path, vars plugins)
    requirements.yml                           <- collections to install
    .sops.yaml                                 <- age public keys SOPS encrypts for
    inventory/hosts.yml                        <- target machines and groups
    inventory/group_vars/all/main.yml          <- non-secret variables for every host (domain, domain_dn, WinRM, allow_reboot)
    inventory/group_vars/all/ad.yml            <- what the domain contains: OUs, departments, groups, users, GPOs
    inventory/group_vars/all/secrets.sops.yml  <- SOPS-encrypted secrets (gitignored, shared out of band)
    vars/secrets.sops.yml.example              <- secrets template (committed)
    roles/dc01/                                <- dc01 role (README, vars, tasks/{main,forest,users,gpo}.yml)

Where a variable goes:
- `roles/<role>/vars/main.yml`: how to build that one machine (prefixed with the role name, e.g. `dc01_`)
- `inventory/group_vars/all/ad.yml`: what the domain contains, readable by every role (prefixed `ad_`)
- `inventory/group_vars/all/main.yml`: settings for every host
- Roles only *read* shared values like `allow_reboot`; a role that set its own copy would silently override it.

To add a user, department or GPO, edit `ad.yml` and run
`ansible-playbook site.yml --tags ad`; no task changes are needed.

## Known issues

**dc01 sits on "Applying computer settings" after promotion.** Normal on the
first boot as a DC (AD database, SYSVOL and DNS are being set up); it can
take 10-20 minutes. If Ansible's reboot wait (10 minutes) times out, just
re-run the same command once the login screen appears: promotion is already
done and the run continues with users and GPOs.

**"couldn't resolve module/action 'microsoft.ad.gpo_link'"** means the
playbook was edited to the newer module name. In microsoft.ad 1.12.x the GPO
link module is `microsoft.ad.gpo`; it is renamed `gpo_link` in a later
release (with a deprecation warning on the old name). Check your version
with `ansible-galaxy collection list microsoft.ad`.

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
