# MongoDB — Cheatsheet

Commandes fréquentes pour `mongosh` et `kubectl` dans le contexte K8s (replica set : 2 nœuds + 1 arbiter).

---

## Connexion

### Option 1 : NodePort (port 30017 ouvert dans le security group)

```bash
# Depuis l'extérieur (NodePort)
mongosh --host <MASTER_IP> --port 30017 -u admin -p <PASSWORD>

# Connexion à une base spécifique
mongosh "mongodb://myapp:pwd@<MASTER_IP>:30017/myappdb"
```

### Option 2 : Port-forward (tunnel via kubectl, pas besoin d'ouvrir le port 30017)

```bash
# 1. Lancer le port-forward (garder le terminal ouvert)
kubectl port-forward -n mongodb svc/mongodb 27017:27017

# 2. Dans un autre terminal, se connecter sur localhost
mongosh "mongodb://admin:<PASSWORD>@localhost:27017/admin"

# Ou avec mongosh classique
mongosh --host localhost --port 27017 -u admin -p <PASSWORD>

# Connexion à une base spécifique
mongosh "mongodb://myapp:pwd@localhost:27017/myappdb"
```

**Prérequis port-forward :** `kubectl` configuré avec KUBECONFIG pointant vers le cluster.

### Option 3 : Depuis un pod dans le cluster (URI replica set)

```bash
# URI replica set (recommandé pour le failover)
kubectl run -it --rm mongosh --image=mongo:7 --restart=Never -n mongodb -- \
  mongosh "mongodb://admin:<PASSWORD>@mongodb-0.mongodb-headless.mongodb.svc.cluster.local:27017,mongodb-1.mongodb-headless.mongodb.svc.cluster.local:27017/admin?replicaSet=rs0"

# URI via le service (route vers le primary)
kubectl run -it --rm mongosh --image=mongo:7 --restart=Never -n mongodb -- \
  mongosh "mongodb://admin:<PASSWORD>@mongodb.mongodb.svc.cluster.local:27017/admin"
```

---

## Port-forward — Détails

```bash
# Syntaxe
kubectl port-forward -n <NAMESPACE> svc/<SERVICE> [LOCAL_PORT]:<REMOTE_PORT>

# MongoDB (namespace mongodb, service mongodb)
kubectl port-forward -n mongodb svc/mongodb 27017:27017

# Équivalent via le pod directement
kubectl port-forward -n mongodb pod/mongodb-0 27017:27017

# Port local personnalisé (ex. 28017 si 27017 est déjà utilisé)
kubectl port-forward -n mongodb svc/mongodb 28017:27017
# Connexion : mongosh --host localhost --port 28017 -u admin -p <PWD>

# Lancer en arrière-plan (pour backup/restore, scripts)
kubectl port-forward -n mongodb svc/mongodb 27017:27017 &
PF_PID=$!
mongodump --host localhost --port 27017 -u admin -p <PWD> --authenticationDatabase admin --out ./backup
kill $PF_PID
```

Le port-forward crée un tunnel via l'API Kubernetes. Le terminal doit rester ouvert sauf si lancé en arrière-plan (`&`).

---

## Bases de données

```javascript
// Lister les bases
show dbs

// Créer / utiliser une base
use myappdb

// Supprimer la base courante
db.dropDatabase()

// Taille de la base
db.stats()
```

---

## Collections

```javascript
// Lister les collections
show collections

// Créer une collection
db.createCollection("users")

// Supprimer une collection
db.users.drop()

// Stats d'une collection
db.users.stats()

// Nombre de documents
db.users.countDocuments()
```

---

## CRUD — Create

```javascript
// Insérer un document
db.users.insertOne({ name: "Alice", email: "alice@example.com", age: 30 })

// Insérer plusieurs documents
db.users.insertMany([
  { name: "Bob", email: "bob@example.com", age: 25 },
  { name: "Charlie", email: "charlie@example.com", age: 35 }
])
```

---

## CRUD — Read

```javascript
// Tous les documents
db.users.find()

// Avec filtre
db.users.find({ name: "Alice" })

// Avec projection (champs à retourner)
db.users.find({}, { name: 1, email: 1, _id: 0 })

// Un seul document
db.users.findOne({ name: "Alice" })

// Avec opérateurs
db.users.find({ age: { $gt: 25 } })           // age > 25
db.users.find({ age: { $gte: 25, $lte: 35 }}) // 25 <= age <= 35
db.users.find({ name: { $in: ["Alice", "Bob"] }})
db.users.find({ $or: [{ age: 25 }, { name: "Alice" }] })

// Regex
db.users.find({ name: /^ali/i })

// Tri, limite, skip
db.users.find().sort({ age: -1 })         // tri décroissant
db.users.find().limit(10)                  // 10 premiers
db.users.find().skip(5).limit(10)          // pagination
```

---

## CRUD — Update

```javascript
// Modifier un document
db.users.updateOne(
  { name: "Alice" },
  { $set: { age: 31, updated: new Date() } }
)

// Modifier plusieurs documents
db.users.updateMany(
  { age: { $lt: 30 } },
  { $set: { category: "young" } }
)

// Remplacer un document entier
db.users.replaceOne(
  { name: "Alice" },
  { name: "Alice", email: "alice@new.com", age: 31 }
)

// Incrémenter une valeur
db.users.updateOne({ name: "Alice" }, { $inc: { age: 1 } })

// Supprimer un champ
db.users.updateOne({ name: "Alice" }, { $unset: { category: "" } })

// Upsert (insert si pas trouvé)
db.users.updateOne(
  { name: "Diana" },
  { $set: { email: "diana@example.com" } },
  { upsert: true }
)
```

---

## CRUD — Delete

```javascript
// Supprimer un document
db.users.deleteOne({ name: "Bob" })

// Supprimer plusieurs documents
db.users.deleteMany({ age: { $lt: 25 } })

// Supprimer tous les documents (garder la collection)
db.users.deleteMany({})
```

---

## Index

```javascript
// Créer un index
db.users.createIndex({ email: 1 })

// Index unique
db.users.createIndex({ email: 1 }, { unique: true })

// Index composé
db.users.createIndex({ name: 1, age: -1 })

// Lister les index
db.users.getIndexes()

// Supprimer un index
db.users.dropIndex("email_1")

// Supprimer tous les index (sauf _id)
db.users.dropIndexes()

// Expliquer une requête (plan d'exécution)
db.users.find({ email: "alice@example.com" }).explain("executionStats")
```

---

## Aggregation

```javascript
// Pipeline basique
db.users.aggregate([
  { $match: { age: { $gte: 25 } } },
  { $group: { _id: "$category", count: { $sum: 1 }, avgAge: { $avg: "$age" } } },
  { $sort: { count: -1 } }
])

// Compter par valeur d'un champ
db.users.aggregate([
  { $group: { _id: "$category", total: { $sum: 1 } } }
])

// Lookup (jointure)
db.orders.aggregate([
  { $lookup: {
      from: "users",
      localField: "userId",
      foreignField: "_id",
      as: "user"
  }}
])

// Projeter des champs
db.users.aggregate([
  { $project: { name: 1, email: 1, _id: 0 } }
])
```

---

## Utilisateurs et rôles

```javascript
// Créer un utilisateur
use myappdb
db.createUser({
  user: "myapp",
  pwd: "motdepasse",
  roles: [{ role: "readWrite", db: "myappdb" }]
})

// Lister les utilisateurs
use admin
db.getUsers()

// Changer un mot de passe
db.changeUserPassword("myapp", "nouveaumotdepasse")

// Supprimer un utilisateur
db.dropUser("myapp")

// Rôles disponibles : read, readWrite, dbAdmin, dbOwner, userAdmin, clusterAdmin, root
```

---

## Backup / Restore

Remplacer `<HOST>` et le port selon le mode de connexion :
- **NodePort** : `<HOST>=<MASTER_IP>`, port `30017`
- **Port-forward** : lancer `kubectl port-forward -n mongodb svc/mongodb 27017:27017` puis `<HOST>=localhost`, port `27017`

```bash
# Dump complet
mongodump --host <HOST> --port <PORT> -u admin -p <PWD> --authenticationDatabase admin --out ./backup

# Dump d'une base
mongodump --host <HOST> --port <PORT> -u admin -p <PWD> --authenticationDatabase admin --db myappdb --out ./backup

# Dump d'une collection
mongodump --host <HOST> --port <PORT> -u admin -p <PWD> --authenticationDatabase admin --db myappdb --collection users --out ./backup

# Restore complet
mongorestore --host <HOST> --port <PORT> -u admin -p <PWD> --authenticationDatabase admin ./backup

# Restore d'une base
mongorestore --host <HOST> --port <PORT> -u admin -p <PWD> --authenticationDatabase admin --db myappdb ./backup/myappdb

# Export en JSON
mongoexport --host <HOST> --port <PORT> -u admin -p <PWD> --authenticationDatabase admin --db myappdb --collection users --out users.json

# Import depuis JSON
mongoimport --host <HOST> --port <PORT> -u admin -p <PWD> --authenticationDatabase admin --db myappdb --collection users --file users.json
```

**Exemple avec port-forward :**
```bash
kubectl port-forward -n mongodb svc/mongodb 27017:27017 &
mongodump --host localhost --port 27017 -u admin -p <PWD> --authenticationDatabase admin --out ./backup
```

---

## Replica set — Commandes

```javascript
// État du replica set (membres, rôles, santé)
rs.status()

// Configuration du replica set
rs.conf()

// Identifier le primary
rs.isMaster()

// Forcer un stepdown (le primary devient secondary)
rs.stepDown()

// Vérifier le lag de réplication
rs.printReplicationInfo()
rs.printSecondaryReplicationInfo()
```

---

## Commandes kubectl utiles

```bash
# État des pods MongoDB (primary, secondary, arbiter)
kubectl get pods -n mongodb
kubectl describe pod mongodb-0 -n mongodb

# Logs par rôle
kubectl logs -n mongodb mongodb-0 -f          # primary
kubectl logs -n mongodb mongodb-1 -f          # secondary
kubectl logs -n mongodb mongodb-arbiter-0 -f  # arbiter
kubectl logs -n mongodb mongodb-0 --previous  # logs du crash précédent

# Shell dans le primary
kubectl exec -it mongodb-0 -n mongodb -- mongosh -u admin -p <PWD>

# Shell dans le secondary
kubectl exec -it mongodb-1 -n mongodb -- mongosh -u admin -p <PWD>

# Vérifier le service et le NodePort
kubectl get svc -n mongodb

# Vérifier le stockage (PVC) — 2 PVC pour les nœuds données, pas pour l'arbiter
kubectl get pvc -n mongodb

# Port-forward (tunnel vers MongoDB sans ouvrir le NodePort)
kubectl port-forward -n mongodb svc/mongodb 27017:27017
# Puis : mongosh "mongodb://admin:<PWD>@localhost:27017/admin"

# Port-forward en arrière-plan (pour scripts)
kubectl port-forward -n mongodb svc/mongodb 27017:27017 &

# Port-forward vers un port local différent (ex. 27018)
kubectl port-forward -n mongodb svc/mongodb 27018:27017

# Redémarrer un nœud (StatefulSet le recrée)
kubectl delete pod mongodb-0 -n mongodb    # primary
kubectl delete pod mongodb-1 -n mongodb    # secondary

# Vérifier le replica set après redémarrage
kubectl exec -it mongodb-0 -n mongodb -- mongosh -u admin -p <PWD> --eval "rs.status()"
```

---

## Monitoring rapide

```javascript
// État du serveur
db.serverStatus()

// Connexions actives
db.serverStatus().connections

// Opérations en cours
db.currentOp()

// Taille des données
db.stats()

// Top des collections par taille
db.getCollectionNames().forEach(c => {
  const s = db[c].stats();
  print(`${c}: ${Math.round(s.storageSize/1024)}KB, ${s.count} docs`);
})

// État du replica set (résumé rapide)
rs.status().members.forEach(m => {
  print(`${m.name}: ${m.stateStr} (health: ${m.health})`);
})
```

---

## Opérateurs fréquents

| Opérateur | Description | Exemple |
|-----------|-------------|---------|
| `$eq` | Égal | `{ age: { $eq: 25 } }` |
| `$ne` | Différent | `{ age: { $ne: 25 } }` |
| `$gt` / `$gte` | Supérieur / Supérieur ou égal | `{ age: { $gt: 25 } }` |
| `$lt` / `$lte` | Inférieur / Inférieur ou égal | `{ age: { $lt: 30 } }` |
| `$in` | Dans une liste | `{ name: { $in: ["A","B"] } }` |
| `$nin` | Pas dans une liste | `{ name: { $nin: ["A"] } }` |
| `$exists` | Champ existe | `{ email: { $exists: true } }` |
| `$regex` | Expression régulière | `{ name: { $regex: /^ali/i } }` |
| `$and` / `$or` | ET / OU logique | `{ $or: [{a: 1}, {b: 2}] }` |
| `$set` | Modifier un champ | `{ $set: { age: 31 } }` |
| `$unset` | Supprimer un champ | `{ $unset: { tmp: "" } }` |
| `$inc` | Incrémenter | `{ $inc: { count: 1 } }` |
| `$push` | Ajouter à un tableau | `{ $push: { tags: "new" } }` |
| `$pull` | Retirer d'un tableau | `{ $pull: { tags: "old" } }` |
