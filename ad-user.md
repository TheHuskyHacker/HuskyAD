# OSCP AD Cheat Sheet — You Have a User

A Bash script for Active Directory enumeration and exploitation when you have valid domain credentials. Built for the OSCP exam AD set.

**Now with auto-run checks** — fill in your variables and run it. It automatically scans for live hosts, checks common service ports, Kerberoasts, AS-REP Roasts, and pulls quick-win data, then saves everything to `./ad_loot/`.

## Usage

1. Fill in the variables at the top of the script:

```bash
DC_IP="10.10.10.10"
DOMAIN="corp.local"
USER="jsmith"
PASS="Password123"
HASH="aad3b435b51404eeaad3b435b51404ee:7facdc498ed1680c4fd1448319a8c04f"
TARGET="10.10.10.20"
LHOST="10.10.14.5"
LPORT="443"
SUBNET="10.10.10"
```

2. Run the script:

```bash
chmod +x oscp-ad-user.sh
bash oscp-ad-user.sh
```

3. Review the auto-run output in `./ad_loot/`, then copy/paste manual sections from the script as needed.

## What the Auto-Run Does

| Check | Output File | What It Finds |
|-------|-------------|---------------|
| Host sweep | `live_hosts.txt` | All live IPs on the subnet |
| Port scan | `port_scan.txt` | Open AD/service ports (see list below) |
| Kerberoast | `kerberoast.txt` | TGS hashes for offline cracking |
| AS-REP Roast | `asrep.txt` | Hashes from accounts with no pre-auth |
| SMB shares | `shares.txt` | Readable/writable shares |
| Password policy | `passpol.txt` | Lockout threshold before spraying |
| GPP passwords | `gpp.txt` | Group Policy Preference creds |
| User descriptions | `user_descriptions.txt` | Passwords hiding in LDAP descriptions |
| GMSA passwords | `gmsa.txt` | Readable Group Managed Service Account passwords |

### Ports Scanned

```
21 (FTP), 22 (SSH), 25 (SMTP), 53 (DNS), 80 (HTTP), 88 (Kerberos),
111 (RPC), 135 (MSRPC), 139 (NetBIOS), 389 (LDAP), 443 (HTTPS),
445 (SMB), 464 (Kpasswd), 593 (HTTP-RPC), 636 (LDAPS),
1433 (MSSQL), 1521 (Oracle), 2049 (NFS), 3268/3269 (Global Catalog),
3306 (MySQL), 3389 (RDP), 5432 (PostgreSQL), 5985/5986 (WinRM),
8080/8443 (HTTP alt), 9389 (AD Web Services)
```

The scan flags noteworthy findings like WinRM targets, MSSQL for xp_cmdshell, NFS mounts, and FTP anonymous login.

## Manual Sections

After the auto-run, the rest of the script is a copy/paste reference:

| # | Section | What It Covers |
|---|---------|---------------|
| M1 | DNS Enumeration | Zone transfers, reverse lookups |
| M2 | Deeper SMB Enumeration | Spidering shares, null sessions |
| M3 | User & Group Enumeration | netexec, rpcclient, RID brute |
| M4 | LDAP Enumeration | SPN users, AS-REP targets, computers |
| M5 | BloodHound Collection | bloodhound-python one-liner |
| M6 | Password Spraying | netexec/kerbrute spray |
| M7 | Lateral Movement | Check admin access across hosts |
| M8 | Shell Access | evil-winrm, psexec, wmiexec, smbexec, atexec |
| M9 | Credential Dumping | SAM, LSA, DCSync, NTDS.dit |
| M10 | Privilege Escalation | GenericWrite, ForceChangePassword, GMSA, ADCS/Certipy |
| M11 | File Transfer Helpers | HTTP server, certutil, PowerShell, SMB share |
| M12 | MSSQL | xp_cmdshell, database enumeration |
| M13 | Quick Wins Checklist | Pre-flight checklist |

## Requirements

Standard Kali/Parrot tools:

- `nmap`
- `impacket` (psexec, wmiexec, secretsdump, GetUserSPNs, GetNPUsers, mssqlclient)
- `netexec` (formerly crackmapexec)
- `evil-winrm`
- `bloodhound-python`
- `rpcclient` (samba-common-bin)
- `ldapsearch` (ldap-utils)
- `smbclient`
- `hashcat`
- `dig` (dnsutils)
- `certipy-ad` (optional — for ADCS abuse)
- `kerbrute` (optional — grab from GitHub releases)

## Workflow

```
Run script (auto-checks)
    → Crack Kerberoast / AS-REP hashes
    → Review shares, descriptions, GPP for creds
    → Password spray with found passwords
    → Run BloodHound — find shortest path to DA
    → Check lateral movement access
    → Get a shell → dump creds
    → Repeat until Domain Admin
```

## Tips

- **Always check `passpol.txt`** before spraying — know the lockout threshold.
- **Spider shares early** — config files in SYSVOL/NETLOGON often contain credentials.
- **BloodHound first** — the graph shows shortest paths so you don't waste time guessing.
- **Crack everything** — even low-priv service account hashes can unlock lateral movement.
- **Check Certipy** — ADCS misconfigurations (ESC1-ESC8) are common OSCP paths now.
- **If MSSQL is open** — xp_cmdshell is almost always the intended path.

## Author

Aaron Gaddis — [The Husky Hacker](https://thehuskyhacker.com)
