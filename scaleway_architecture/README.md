# Choix de l'architecture – Application SaaS sur Scaleway

Ce document présente les cinq schémas d'architecture étudiés, les compare selon le coût, la sécurité et l'effort d'exploitation, puis justifie le modèle retenu.

## 1. Besoins couverts

- Hébergement de l'application conteneurisée (Docker), avec des conteneurs applicatifs de 4 Go
- Base de données PostgreSQL (15k IOPS, sauvegardes automatiques)
- Cache Redis
- Registre de conteneurs pour les images Docker
- Stockage des documents (S3)
- Accès à l'IA Mistral
- Service de cartographie hébergé sur un serveur Dedibox
- Déploiement automatisé (Argo CD / CI/CD)
- Accès administrateur sécurisé (SSH / bastion)
- Accès Internet sortant pour les mises à jour (patching)

## 2. Schémas étudiés

Chaque proposition existe en deux formats : SVG (image) et draw.io (modifiable).

| # | Fichiers | Résumé |
|---|---|---|
| P1 | `proposal-1-architecture.svg` / `.drawio` | VM privée + Docker/k3s, NLB public + WAF, PostgreSQL et Redis managés, API Mistral publique, bastion SSH |
| P2 | `proposal-2-architecture.svg` / `.drawio` | Comme P1, mais Mistral via **Scaleway Generative APIs** (UE) |
| P3 | `proposal-3-architecture.svg` / `.drawio` | **Kubernetes Kapsule Mutualisé** (3 nœuds BASIC3-X4C-8G) + Argo CD, services managés |
| P4 | `proposal-4-architecture.svg` / `.drawio` | **Serverless Containers** en entrée privée uniquement, derrière le NLB + WAF |
| P5 | `proposal-5-architecture.svg` / `.drawio` | **VPS Dedibox unique** (VPS-START-2-XXL), PostgreSQL et Redis auto-hébergés, DNS chez LWS, sans WAF, SSH exposé |

## 3. Comparaison

Les coûts sont des estimations mensuelles HT (région fr-par). Les prix des bases managées sont approximatifs. Les tokens IA et l'usage S3 / registre ne sont pas inclus.

| Critère | P1 | P2 | P3 | P4 | P5 |
|---|---|---|---|---|---|
| Coût estimé / mois | ~270–300 € | ~270–300 € | ~390 € et plus | ~200–450 € (selon le trafic) | ~100 € |
| Sécurité | Bonne | Très bonne | Très bonne | Très bonne* | La plus faible |
| Exposition Internet | NLB uniquement | NLB uniquement | NLB uniquement | NLB uniquement | VPS directement (443 + SSH) |
| Base de données | Managée, sauvegardes auto | Managée, sauvegardes auto | Managée, sauvegardes auto | Managée, sauvegardes auto | Auto-hébergée sur la même machine |
| Disponibilité | VM unique | VM unique | Élevée (3 nœuds, autoheal) | Élevée (gérée par Scaleway) | Serveur unique (point de défaillance) |
| Effort d'exploitation | Moyen | Moyen | Moyen à élevé (Kubernetes) | Faible | Élevé (tout à votre charge) |
| Données IA dans l'UE | Non garanti (API publique) | Oui | Oui | Oui | Oui |

\* P4 : à valider. La prise en charge d'un NLB avec en backend l'endpoint privé d'un Serverless Container doit être confirmée.

## 4. Modèle retenu : Proposition 2

**Choix : P2 – VM en réseau privé, services managés et Scaleway Generative APIs.**

### Pourquoi

1. **Sécurité adaptée à un SaaS**
   - La VM n'a aucune IP publique. Le NLB, protégé par le WAF, est le seul point d'entrée.
   - PostgreSQL et Redis ne sont accessibles que depuis le réseau privé (VPC).
   - L'accès administrateur passe uniquement par le bastion SSH de la Public Gateway, avec une liste d'IP autorisées.
   - Les appels IA restent chez Scaleway, dans l'UE, ce qui est un argument RGPD auprès des clients.
2. **Protection des données clients**
   - La base managée assure les sauvegardes automatiques et la restauration. La donnée la plus critique ne dépend pas de scripts maison.
3. **Coût maîtrisé**
   - Une seule VM pour le calcul, soit environ 3 fois moins cher que P3 pour un niveau de sécurité équivalent.
4. **Évolutif sans refonte**
   - Le réseau, la base, le stockage et le registre restent identiques lors d'un passage vers P3 (Kubernetes).

### Pourquoi pas les autres

- **P1** : même coût que P2, mais les appels IA sortent vers l'API publique Mistral. P2 est donc préférable.
- **P3** : plus robuste, mais plus cher et plus complexe à exploiter. À envisager quand la charge ou le besoin de haute disponibilité le justifient.
- **P4** : séduisant (pas de serveur à gérer, paiement à l'usage), mais le schéma NLB vers entrée privée reste à valider. Les coûts sont aussi moins prévisibles avec des conteneurs de 4 Go toujours actifs, et il n'y a pas d'Argo CD.
- **P5** : le moins cher, mais l'application, la base et les sauvegardes sont sur une seule machine, SSH est exposé, il n'y a pas de WAF, et l'exploitation de la base est entièrement à votre charge. Ce modèle convient à un MVP ou une démo, pas à un SaaS en production avec des données clients. Le VPS Dedibox n'étant pas dans le VPC Scaleway, une base managée y serait accessible uniquement via un endpoint public (ACL + TLS).

## 5. Optimisation des coûts (sans réduire la sécurité)

- Choisir des instances **BASIC2** (environ 2 fois moins chères que POP2) et redimensionner selon la charge réelle.
- Démarrer PostgreSQL sur **un seul nœud** avec sauvegardes automatiques, puis activer la **haute disponibilité** avec les premiers clients payants.
- Souscrire un **Savings Plan** (jusqu'à -25 % sur les instances) une fois la consommation stable.
- Si le WAF Scaleway sur le NLB n'est pas disponible ou trop coûteux, utiliser **Cloudflare** (offre gratuite ou Pro) devant le NLB pour le WAF et la protection DDoS.
- Utiliser **Cockpit** (offre incluse) pour la supervision de base.

## 6. Trajectoire d'évolution

| Étape | Architecture | Déclencheur |
|---|---|---|
| 1. MVP / premiers clients | **P2** | Démarrage |
| 2. SaaS en croissance | P2 + PostgreSQL HA + 2e VM derrière le NLB | Engagements de disponibilité envers les clients |
| 3. Passage à l'échelle | **P3** (Kapsule), puis Dedicated-4 | Nombreux services, besoin de SLA et de journaux d'audit |

## 7. Points à vérifier avant la mise en œuvre

- [ ] Disponibilité et tarif du **WAF** associable au Load Balancer Scaleway (sinon, Cloudflare)
- [ ] Disponibilité du niveau **15k IOPS** pour le type de nœud PostgreSQL et la région choisis
- [ ] Modèles **Mistral** disponibles dans Generative APIs et tarification par token
- [ ] Connexion sécurisée vers le **Dedibox cartographie** (liste d'IP autorisées via l'IP de la Public Gateway, ou token / mTLS)
- [ ] Rétention des sauvegardes PostgreSQL et **test de restauration**
- [ ] Gestion des secrets (Secret Manager) et rotation des clés SSH et API

## 8. Hypothèses

- Région Scaleway **fr-par**.
- Prix issus du catalogue public Scaleway au moment de l'étude (HT, 730 h par mois). Ils sont susceptibles d'évoluer.
- Charge applicative de référence : environ 3 conteneurs applicatifs de 4 Go.
