# MongoDB Standalone (image officielle mongo:8.0)

Déploiement MongoDB en mode **standalone** (1 pod) via des manifests Kubernetes.
Utilise l'image officielle `mongo:8.0` (Docker Hub, gratuite et maintenue par MongoDB).
Adapté aux VMs avec peu de ressources (1-2 vCPU / 2 GB RAM).

> Pour un déploiement en **replica set** (Bitnami, VM 4 GB+), voir `tools/mongodb/`.

## Structure

```
tools/mongodb-standalone/
├── install.sh               # Script d'installation
├── manifests/
│   ├── namespace.yaml       # Namespace mongodb
│   ├── secret.yaml          # Mots de passe (à personnaliser)
│   ├── configmap.yaml       # Script init : création user applicatif
│   ├── statefulset.yaml     # Pod MongoDB + PVC 1Gi
│   └── service.yaml         # NodePort 30017 + headless
└── README.md
```

## Configuration

Éditer `manifests/secret.yaml` :

| Clé | Description |
|---|---|
| `MONGO_INITDB_ROOT_USERNAME` | Utilisateur root (défaut : `admin`) |
| `MONGO_INITDB_ROOT_PASSWORD` | Mot de passe root **(obligatoire)** |
| `MONGO_APP_USERNAME` | Utilisateur applicatif |
| `MONGO_APP_PASSWORD` | Mot de passe applicatif |
| `MONGO_APP_DATABASE` | Base de données applicative |

## Installation

```bash
# Sur le serveur (avec kubectl configuré)
sudo bash install.sh
```

## Désinstallation

```bash
kubectl delete -f manifests/
kubectl delete pvc -n mongodb -l app=mongodb
```

## Connexion

```bash
# Root (base admin)
mongosh --host <NODE_IP> --port 30017 \
  -u admin -p <MOT_DE_PASSE> \
  --authenticationDatabase admin

# Utilisateur applicatif
mongosh --host <NODE_IP> --port 30017 \
  -u myappuser -p <MOT_DE_PASSE> \
  --authenticationDatabase myappdb
```

## Ressources (VM 2 GB)

| | CPU | RAM |
|---|---|---|
| Requests | 200m | 256Mi |
| Limits | 500m | 512Mi |
