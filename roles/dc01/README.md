# dc01 Role

Builds dc01 (Windows Server 2016), the first domain controller of the
`yabe.corp` Active Directory domain for the Yabe online marketplace.

Nothing in this role hardens Windows: security settings stay at their
defaults. The GPO is cosmetic on purpose.

## What it does

**Forest** (`tasks/forest.yml`): promotes dc01 to a domain controller
- Installs Active Directory Domain Services and DNS
- Creates the forest and domain `yabe.corp` (NetBIOS name `YABE`) at the
  Windows Server 2016 functional level, the lowest level dc02 (Server 2025)
  can join
- Stops and asks for a reboot unless `allow_reboot=true` (see below)
- Waits until AD answers before anything else runs

**Users** (`tasks/users.yml`): fills AD with Yabe's staff
- OUs `Yabe Users` (one child OU per department) and `Yabe Groups`
- One security group per department, e.g. `Payments Staff`
- 30 employees, 5 per department, with job titles; usernames are
  first initial + `.` + surname (`m.okafor`)

**GPO** (`tasks/gpo.yml`): creates, fills and links every GPO in `ad_gpos`.
All are cosmetic/convenience User Configuration settings; each shows a
different Group Policy behaviour:

| GPO | Linked to | Does | Shows |
|-----|-----------|------|-------|
| `Yabe - Desktop Wallpaper` | `Yabe Users` (everyone) | company wallpaper, Fill | basic GPO + inheritance to child OUs |
| `Yabe - Engineering Wallpaper` | Engineering | a different wallpaper | precedence: the closer link wins a conflict |
| `Yabe - Help Desk Homepage` | Customer Support, Seller Services | Edge home/startup page `http://intranet.yabe.corp` | one GPO linked to several OUs |
| `Yabe - Marketing Brand Lock` | Marketing | "Prevent changing desktop background" | merging: adds to the inherited wallpaper GPO |

Departments: Engineering, Customer Support, Trust and Safety,
Seller Services, Payments, Marketing.

## Where the settings live

| File | Holds |
|------|-------|
| `roles/dc01/vars/main.yml` | how to build dc01: functional levels, NetBIOS name |
| `inventory/group_vars/all/ad.yml` | what the domain contains: OUs, departments, groups, users, GPOs |
| `inventory/group_vars/all/main.yml` | `domain`, `domain_dn`, `allow_reboot` |
| `inventory/group_vars/all/secrets.sops.yml` | `safe_mode_password`, `ad_user_password` |

`ad.yml` is outside the role because it describes the domain, not one
machine; other roles (fs01-win shares, app01 sites) can read the same names.

## Usage

| Tag | Description |
|-----|-------------|
| `dc01` | Everything in this role |
| `forest` / `infra` | Promotion only |
| `users` | OUs, groups and users |
| `gpo` | Group Policy only |
| `ad` | Everything stored in AD (users + GPO); re-run after editing `ad.yml` |

The "wait for AD" check runs with every tag, so a tag-only run can't start
before AD is ready.

### First run (promotion needs a reboot)

    ansible-playbook site.yml --limit dc01
    # Ansible stops dc01 and says to reboot. Then:
    ansible dc01 -m ansible.windows.win_reboot
    ansible-playbook site.yml --limit dc01

Or let Ansible reboot for you in one run:

    ansible-playbook site.yml --limit dc01 -e allow_reboot=true

After promotion dc01 has no local accounts: `Administrator` is now
`YABE\Administrator` with the same password, so the login in the secrets
file keeps working unchanged.

### Later runs

    ansible-playbook site.yml --tags users     # after adding users
    ansible-playbook site.yml --tags gpo       # after adding a GPO

To add a user, department or GPO, edit `inventory/group_vars/all/ad.yml`;
no task changes are needed.

## Checking the result (on dc01, PowerShell)

    Get-ADDomain                                            # domain exists
    Get-ADUser -Filter * -SearchBase "OU=Yabe Users,DC=yabe,DC=corp" | Measure-Object   # 30
    Get-ADGroupMember "Payments Staff"
    Get-GPOReport -Name "Yabe - Desktop Wallpaper" -ReportType Html -Path C:\gpo.html
    (Get-GPInheritance -Target "OU=Yabe Users,DC=yabe,DC=corp").GpoLinks
    # every GPO a Marketing user receives, in order (inherited + direct)
    (Get-GPInheritance -Target "OU=Marketing,OU=Yabe Users,DC=yabe,DC=corp").InheritedGpoLinks

To see the wallpaper itself, log on as one of the 30 users on a
domain-joined member server (by default normal users can't log on to a DC,
and we leave that default alone), then run `gpresult /r`.

## Notes

- **dc02** is not handled here. It joins later as an additional DC through
  its own role; users and GPOs reach it by AD replication, so this role's
  user and GPO tasks never need to run there.
- **Removing** a user, group or GPO setting from `ad.yml` does not delete it
  from AD; delete it by hand. Ansible here only creates and updates.
