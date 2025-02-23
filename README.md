# Infrastructure

My infrastructure at a glance.

## 🇹🇼 Lumos

### [Nginx Proxy Manager](https://npm.tomy.me)

![Nginx Proxy Manager Status](https://kuma.tomy.me/api/badge/6/status)
![Nginx Proxy Manager Uptime](https://kuma.tomy.me/api/badge/6/uptime/24)

```
ansible-playbook -l lumos service/nginx-proxy-manager/playbook.yml
```

### [Portainer](https://portainer.tomy.me)

![Portainer Status](https://kuma.tomy.me/api/badge/5/status)
![Portainer Uptime](https://kuma.tomy.me/api/badge/5/uptime/24)

```
ansible-playbook -l lumos service/portainer/playbook.yml
```

```
ansible-playbook -l linode_tokyo2,digitalocean_sgp1 service/portainer-agent/playbook.yml
```

### [1Password Connect](https://op-connect.tomy.me)

![1Password Connect Status](https://kuma.tomy.me/api/badge/10/status)
![1Password Connect Uptime](https://kuma.tomy.me/api/badge/10/uptime/24)

```
ansible-playbook -l lumos service/1password-connect/playbook.yml
```

### [NocoDB](https://nocodb.tomy.me)

![NocoDB Status](https://kuma.tomy.me/api/badge/19/status)
![NocoDB Uptime](https://kuma.tomy.me/api/badge/19/uptime/24)

```
ansible-playbook -l lumos service/nocodb/playbook.yml
```

### [PiHole](https://pihole.tomy.me)

![PiHole Status](https://kuma.tomy.me/api/badge/21/status)
![PiHole Uptime](https://kuma.tomy.me/api/badge/21/uptime/24)

```
ansible-playbook -l lumos service/pihole/playbook.yml
```

### [Wireguard](https://wg.tomy.me)

![Wireguard Status](https://kuma.tomy.me/api/badge/22/status)
![Wireguard Uptime](https://kuma.tomy.me/api/badge/22/uptime/24)

```
ansible-playbook -l lumos service/wireguard/playbook.yml
```

## 🇯🇵 Mailcow

### [Mailcow](https://mailcow.tomy.me)

![Mailcow Status](https://kuma.tomy.me/api/badge/13/status)
![Mailcow Uptime](https://kuma.tomy.me/api/badge/13/uptime/24)

## 🇯🇵 Tubee

### [Tubee](https://tubee.tomy.tech)

![Tubee Status](https://kuma.tomy.me/api/badge/1/status)
![Tubee Uptime](https://kuma.tomy.me/api/badge/1/uptime/24)

## 🇸🇬 PQuill

### [Plausible Analytics](https://a.tomy.me)

![Plausible Analytics Status](https://kuma.tomy.me/api/badge/8/status)
![Plausible Analytics Uptime](https://kuma.tomy.me/api/badge/8/uptime/24)

```
ansible-playbook -l pquill service/plausible-analytics/playbook.yml --extra-vars "docker_network=caddy domain=a.tomy.me"
```

### [Remark42](https://remark42.tomy.me)

![Remark42 Status](https://kuma.tomy.me/api/badge/23/status)
![Remark42 Uptime](https://kuma.tomy.me/api/badge/23/uptime/24)

```
ansible-playbook -l pquill service/remark42/playbook.yml --extra-vars "docker_network=caddy domain=remark42.tomy.me"
```


### [Uptime Kuma](https://kuma.tomy.me)

```
ansible-playbook -l pquill service/uptime-kuma/playbook.yml
```
