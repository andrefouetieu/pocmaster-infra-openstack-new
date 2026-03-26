# Plan observabilité — notes et arbitrages

Espace pour tes observations sur le mode de déploiement choisi (GitOps, Helm via `tools/`, Ansible, Terraform, etc.) et les ajustements avant implémentation.

## Contexte

- Stack cible : Prometheus, Grafana, Loki, gestion des alertes (Alertmanager).
- Contrainte : installation sur Kubernetes avec Helm.

## Observations

_(À compléter.)_

## Décisions

_(À compléter : par exemple choix hybride tools + Argo CD, namespaces, exposition, secrets.)_

## Liens utiles dans ce dépôt

- [ARGOCD.md](ARGOCD.md) — modes d’installation et usage GitOps.
- Patron outils : `.cursor/rules/tool-installation-pattern.mdc` (scope `infra_platform` pour les hooks Terraform `install_*`).
