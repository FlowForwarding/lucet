Put the user's authorized_key file here.

```
ssh-keygen -t rsa -f id_rsa
cp id_rsa.pub authorized_keys
```

Then use the id_rsa as your private key, for example:

```
mkdir ~/.lucet_ssh
chmod 700 ~/.lucet_ssh
cp id_rsa id_rsa.pub ~/.lucet_ssh
chmod 600 ~/.lucet_ssh/id_rsa
ssh hostname -p 22333 -i ~/.lucet_ssh/id_rsa -o UserKnownHostsFile=~/.lucet_ssh/known_hosts
```

To quit the erlang shell invoke `exit().`.
