# MinIO Linux Installation

Installation directe de MinIO sur Linux sans Docker, avec configuration Nginx, SSL, et gestion via systemd.

## Architecture

```
┌─────────────────────────────────────┐
│  HTTPS (s3.v2.selys.app)            │
│  HTTPS (minio.v2.selys.app)         │
└──────────────┬──────────────────────┘
               │ (port 443)
        ┌──────▼──────────┐
        │  Nginx Reverse  │
        │  Proxy (HTTPS)  │
        └──────┬──────────┘
               │
      ┌────────┼────────┐
      │                 │
    9005              9006
      │                 │
┌─────▼─────┐   ┌──────▼──────┐
│ MinIO API │   │ MinIO       │
│ (S3)      │   │ Console     │
└───────────┘   └─────────────┘
      ↓                 ↓
  /var/lib/minio (shared data directory)
```

## Installation rapide

### 1. Clone et configure
```bash
cd /var/www/minio-configs-v2/linux
cp ../. env .env  # ou édite .env avec tes credentials
```

### 2. Deploy complet
```bash
cd /var/www/minio-configs-v2/linux
sudo make deploy
```

Cela va :
- Installer MinIO via deb (curl + dpkg)
- Créer l'utilisateur `minio` et les répertoires
- Installer le service systemd
- Obtenir les certificats SSL (Certbot)
- Configurer Nginx comme reverse proxy
- Initialiser les buckets

### 3. Vérify l'installation
```bash
make status      # État du service
make logs        # Logs en direct
```

## Variables d'environnement

Édite `../.env` :
```bash
MINIO_ROOT_USER=dev.selys-africa
MINIO_ROOT_PASSWORD=JjSJWms_qRMkp#vQMQ
MINIO_SERVER_URL=https://s3.v2.selys.app
MINIO_BROWSER_REDIRECT_URL=https://minio.v2.selys.app
```

## Ports

- **MinIO API** : 127.0.0.1:9005 (internal)
- **MinIO Console** : 127.0.0.1:9006 (internal)
- **Nginx HTTP** : 0.0.0.0:80
- **Nginx HTTPS** : 0.0.0.0:443

## Commandes utiles

```bash
# Status du service
sudo systemctl status minio

# Logs en direct
sudo journalctl -u minio -f

# Restart le service
sudo systemctl restart minio

# Arrêter
sudo systemctl stop minio

# Démarrer
sudo systemctl start minio

# Voir les buckets
mc ls local/

# Vérifier la santé de l'API
curl -s http://127.0.0.1:9005/minio/health/live
```

## Structure des fichiers

```
linux/
├── Makefile                      # Targets de déploiement
├── minio.service                 # Unité systemd
├── minio.env                     # Variables d'environnement
├── nginx/
│   └── minio.v2.selys.app.conf   # Configuration Nginx reverse proxy
├── scripts/
│   └── bucket-init.sh            # Script d'initialisation des buckets
└── README.md
```

## Dépannage

### Port 9005 occupé
```bash
sudo lsof -i :9005
sudo kill <PID>
```

### MinIO ne démarre pas
```bash
sudo systemctl status minio
sudo journalctl -u minio -n 50
```

### Reinit des buckets
```bash
cd /var/www/minio-configs-v2/linux
bash scripts/bucket-init.sh
```

## Désinstallation

```bash
cd /var/www/minio-configs-v2/linux
sudo make clean  # Arrête le service et supprime les données
```

Puis si tu veux vraiment supprimer MinIO :
```bash
sudo dpkg -r minio
sudo deluser minio
```

## Documentation

- [MinIO Docs](https://docs.min.io)
- [Nginx Reverse Proxy](https://docs.min.io/aistor/deployment/nginx/)
