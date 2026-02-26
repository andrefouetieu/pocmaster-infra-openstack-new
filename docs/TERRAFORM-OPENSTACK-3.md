# Passage au provider OpenStack 3.x

Tu utilises actuellement le provider **~> 1.52.1**. La version **3.4.0** (ou 3.x) introduit des **changements incompatibles** : certaines ressources ont été supprimées au profit des API Neutron (networking).

---

## Ce qui a été fait dans ce repo

Le **module** `terraform/modules/instance` a été adapté pour être **compatible 1.x et 3.x** :

- **IP flottante aléatoire** : plus de `openstack_compute_floatingip_associate_v2`. On utilise un data source `openstack_networking_port_v2` (port de l’instance via `device_id`), puis on crée `openstack_networking_floatingip_v2` avec **`port_id`** pour associer directement.
- **IP flottante fixe** : data source `openstack_networking_floatingip_v2` pour récupérer l’IP existante, puis **`openstack_networking_floatingip_associate_v2`** (Neutron) avec `floating_ip` + `port_id` pour l’association.

Tu peux donc passer le provider en **~> 3.0.0** (ou 3.4.0) dans `01_vps` et `02_cluster` sans modifier d’autres ressources.

---

## Impact sur ce projet (référence)

| Ressource | Statut en 3.x | Action dans le repo |
|-----------|---------------|----------------------|
| `openstack_compute_floatingip_associate_v2` | **Supprimée** | Déjà remplacée dans `modules/instance` (port_id + floatingip_associate_v2 Neutron) |
| Autres ressources (keypair, instance, network, secgroup, etc.) | Conservées | Aucune |

---

## Recommandations

1. **Lire le changelog** du provider :  
   https://github.com/terraform-provider-openstack/terraform-provider-openstack/blob/main/CHANGELOG.md  
   Vérifier les sections 2.x → 3.x pour d’éventuelles autres breaking changes (ex. `openstack_compute_volume_attach_v2`, data sources).

2. **Tester d’abord** sur une copie du state ou un stack de test (ex. 02_cluster sans prod) :  
   - Mettre `version = "~> 3.4.0"` (ou `"~> 3.0.0"`) dans `required_providers`.  
   - Lancer `terraform init -upgrade`.  
   - Corriger les erreurs (remplacement de `openstack_compute_floatingip_associate_v2` comme ci-dessus).  
   - Faire un `terraform plan` et vérifier qu’il n’y a pas de destroy/recreate inattendu.

3. **State existant** : après correction du code, le state reste valide ; les ressources existantes (instances, IP flottantes, etc.) ne sont pas recréées tant que les adresses dans le state correspondent aux nouvelles ressources (par ex. après remplacement de `openstack_compute_floatingip_associate_v2` par une association Neutron, une première exécution peut proposer de supprimer l’ancienne ressource du state et d’en ajouter une nouvelle ; à valider avec précaution).

4. **Faire la mise à jour** d’abord dans **01_vps** ou **02_cluster** (un seul stack), vérifier `plan` et `apply`, puis appliquer à l’autre stack.

En résumé : **oui, passer à 3.4.0 aura un impact** tant que `openstack_compute_floatingip_associate_v2` est utilisée. Une fois le module instance adapté pour n’utiliser que l’API Neutron pour les IP flottantes, le reste des ressources utilisées ici devrait être compatible 3.x.
