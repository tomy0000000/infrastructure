# Infrastructure

My infrastructure at a glance.

## 🗺 Map

- 🇹🇼 Lumos
  - [K-Backend](./k-backend.md)
- Vercel
  - [K Frontend](./k-frontend.md)

### Portainer Agent

```shell
ansible-playbook -l linode_tokyo2,digitalocean_sgp1 service/portainer-agent/playbook.yml
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
