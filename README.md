Termux
------

## Generate ssh key-pair
1) pkg update && pkg install openssh
2) ssh-keygen -t ed25519

## Set up ssh

3) nano ~/.ssh/config

Ja sitten esim:

```
Host miaucloud-nixos
    HostName 64.226.104.65
    User zairex
    IdentityFile ~/.ssh/id_ed25519
```

