from ldap3 import Server, Connection, MODIFY_ADD, ALL
from getpass import getpass

SERVER_URI = 'dc.example.com'
BASE_DN = 'DC=example,DC=com'
DOMAIN = 'example.com'
SSH_KEY_ATTR = 'altSecurityIdentities'

def cleanup(conn):
    conn.unbind()
    exit(0)

def generate_keypair():
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.hazmat.primitives import serialization
    private_key = rsa.generate_private_key(
        public_exponent = 65537,
        key_size = 3072
    )
    private_pem = private_key.private_bytes(
        encoding = serialization.Encoding.PEM,
        format = serialization.PrivateFormat.OpenSSH,
        encryption_algorithm = serialization.NoEncryption()
    ).decode("utf-8")
    print(f"Generated private key:\n\n{private_pem}\n\n^^^ SAVE THIS TO ~/.ssh/id_rsa, YOU WILL NOT SEE IT AGAIN ^^^")

    public_key = private_key.public_key()
    public_pem = public_key.public_bytes(
        encoding = serialization.Encoding.OpenSSH,
        format = serialization.PublicFormat.OpenSSH
    ).decode("utf-8")
    # print(f"Corresponding public key:\n{public_pem}")
    return public_pem

def main():
    username = input('LDAP Username: ')
    password = getpass('LDAP Password: ')
    ssh_key = input('SSH Public Key (blank to generate new keypair): ')
    if (ssh_key == ''):
        ssh_key = generate_keypair()

    filter = f"(sAMAccountName={username})"
    server = Server(SERVER_URI)
    conn = Connection(server, user=f"{username}@{DOMAIN}", password=password)
    if not (conn.bind()):
        print("Error: unable to bind LDAP!")
        cleanup(conn)

    if not (conn.search(BASE_DN, filter, attributes=['sAMAccountName', 'sshPublicKeys'])):
        print("Error: unable to find user!")
        cleanup(conn)

    user = conn.entries[0]
    if (conn.modify(user.entry_dn, {SSH_KEY_ATTR: [(MODIFY_ADD, [ssh_key])]})):
        print("Successfully updated SSH public key.")
        cleanup(conn)
    else:
        print(f"Attempt to update public key failed with result: {conn.last_error}")
        cleanup(conn)

if __name__ == "__main__":
    main()
