# ClaudePaper — papier intelligent pour iPad, Apple Pencil et Claude

ClaudePaper transforme l'iPad en feuille de papier reliée à Claude : tu écris tes réponses **à la main avec l'Apple Pencil** (quantificateurs ∀ ∃, ensembles, ε-δ…), l'app les transcrit en texte, et Claude (le modèle de ton choix) corrige, donne des indices et enchaîne les questions **directement sur la page**.

Le projet est un **App Playground** (`ClaudePaper.swiftpm`) : il s'ouvre sans Mac dans **Swift Playgrounds sur l'iPad**, et aussi dans **Xcode** sur Mac.

## Ce que fait l'app

- **Page blanche défilante** : la question de Claude est affichée en haut, tu réponds en dessous au Pencil. La page s'allonge toute seule pour les longues réponses (papier blanc, lignes ou quadrillage, encre noire même en mode sombre).
- **Indice** (en bas à gauche) : Claude te débloque sans donner la réponse, en tenant compte de ce que tu as déjà écrit (l'image de la page lui est envoyée).
- **Finir** (en bas à droite) : ta réponse est transcrite, tu peux la relire et la corriger, puis Claude l'évalue. Le retour (correct / partiel / incorrect, explication, correction) s'affiche sur la page ; si c'est bon, **Question suivante** ouvre une nouvelle page avec la question proposée.
- **Onglets Page / Discussion** dans la barre du haut, plus les boutons **Aide** (envoie ta page à Claude dans la discussion) et **Question** (ouvre le champ de saisie). La barre latérale permet de **changer de discussion** ou d'en créer une.
- **Cours joints** : PDF, texte ou photos envoyés à Claude (trombone dans la discussion ou feuille « Nouvel exercice »). Exemple : joins ton cours de topologie, demande « fais-moi réviser, niveau L3 », et réponds aux questions page après page.
- **Historique enregistré** : discussions, pages manuscrites, transcriptions et évaluations sont sauvegardées dans *Fichiers → Sur mon iPad → ClaudePaper*.

### Comment l'écriture est reconnue

1. **Sur l'iPad** (framework Vision, français puis anglais) : rapide et gratuit, mais il ne connaît pas les symboles mathématiques.
2. **Analyse de l'image par Claude** : la page est rendue en image (encre noire sur blanc) et envoyée au modèle de transcription (Claude Sonnet 5 par défaut) avec un schéma de sortie strict ; il renvoie une transcription Unicode fidèle (∀, ∃, ∈, ⊂, ⇒, ε, δ, indices…) et une confiance. En mode **Automatique** (défaut), cette étape se déclenche dès que le texte contient des maths ou que la confiance de l'iPad est faible.
3. **Repli demandé par le tuteur** : si Claude n'arrive pas à interpréter la transcription, il répond `needs_image = true` ; l'app envoie alors automatiquement l'image de la page, et la lecture faite par Claude est enregistrée comme transcription de référence.

Avant l'envoi, une feuille de relecture montre l'image, le texte reconnu (modifiable) et un bouton « Analyser l'image avec Claude » (désactivable dans les réglages).

## Installation

### Sur l'iPad (sans Mac)

1. Installe **Swift Playgrounds** (App Store, gratuit, version 4.5 ou plus récente).
2. Récupère le dossier `ClaudePaper.swiftpm` sur l'iPad (par exemple : télécharger le dépôt en ZIP depuis GitHub, l'ouvrir dans Fichiers, puis toucher `ClaudePaper.swiftpm`).
3. Il s'ouvre dans Swift Playgrounds : touche **Exécuter**. L'app tourne en plein écran sur l'iPad.

### Sur Mac (Xcode 15 ou plus récent)

1. Ouvre `ClaudePaper.swiftpm` avec Xcode (Fichier → Ouvrir).
2. Choisis ton iPad (ou un simulateur iPad) et lance. Pour installer sur un iPad physique, sélectionne ton équipe de signature dans *Signing & Capabilities* (ou renseigne `teamIdentifier` dans `Package.swift`).

Si `appIcon: .placeholder(icon: .pencil)` est refusé par ta version de Swift Playgrounds, remplace `.pencil` par `.bicycle` (icône par défaut) dans `Package.swift`.

## Connexion à Claude (clé API)

L'app parle directement à l'API Anthropic (`https://api.anthropic.com/v1/messages`) avec **ta clé API** :

1. Va sur <https://console.anthropic.com/settings/keys>, crée une clé et ajoute un crédit.
2. Dans l'app, ouvre **Réglages** (roue dentée) et colle la clé. Elle est stockée dans le trousseau de l'iPad et n'est envoyée qu'à `api.anthropic.com`.

> Un abonnement Claude Pro/Max (claude.ai) ne peut pas être utilisé depuis une app tierce : il faut une clé API, facturée à l'usage.

### Choix du modèle

Réglable dans les réglages (pour le tuteur, la discussion et la lecture de l'écriture) et par discussion (menu « Plus » → modèle) :

| Modèle | Identifiant API | Usage conseillé | Prix (entrée / sortie, par million de jetons) |
|---|---|---|---|
| Claude Opus 5 (défaut tuteur) | `claude-opus-5` | Rigueur mathématique, réflexion adaptative | 5 $ / 25 $ |
| Claude Fable 5.1 | `claude-fable-5-1` | Le plus puissant ; réflexion toujours active | 10 $ / 50 $ |
| Claude Sonnet 5 (défaut transcription) | `claude-sonnet-5` | Rapide, très bon en lecture d'image | 2 $ / 10 $ |
| Claude Haiku 4.5 | `claude-haiku-4-5` | Le plus économique | 1 $ / 5 $ |

Le niveau d'**effort** (faible → maximum) règle la profondeur de réflexion ; « Élevé » convient au tutorat. Le **repli automatique en cas de refus** (`fallbacks: "default"`, activé par défaut pour Opus 5 et Fable 5.1) rejoue une requête refusée par les classifieurs de sécurité sur un modèle de repli recommandé par Anthropic.

## Détails techniques

- **API** : Messages API en streaming SSE, réflexion adaptative (`thinking: {type: "adaptive"}`), `output_config.effort`, sorties structurées (`output_config.format` avec schéma JSON) pour le mode exercice, images en base64 (JPEG), PDF en blocs `document`, mise en cache du préfixe (`cache_control`), en-tête beta `server-side-fallback-2026-07-01` pour le repli. L'historique envoyé est en ajout seul (aucune modification des tours passés), la consigne système est figée pour toute la session.
- **Écriture** : `PKCanvasView` (PencilKit) au-dessus d'un fond de page synchronisé avec le défilement ; rendu de l'image via `PKDrawing.image(from:scale:)`, `VNRecognizeTextRequest` (`.accurate`, `fr-FR` + `en-US`, correction linguistique coupée en mode maths).
- **Stockage** : JSON par session (`Documents/ClaudePaper/Sessions`), pièces jointes et instantanés de pages dans `Documents/ClaudePaper/Attachments`, clé API dans le trousseau.
- **Structure** : `Models/` (données, catalogue de modèles, réglages), `Services/` (client API, transcription, tuteur, persistance), `ViewModels/SessionViewModel.swift` (orchestration), `Views/` (SwiftUI).

## Limites connues

- Les formules sont affichées en Unicode (pas de rendu LaTeX) ; le tuteur est instruit d'écrire ainsi.
- La reconnaissance sur l'iPad seule ne produit pas de quantificateurs : garde le mode « Automatique » ou « Toujours analyser l'image » pour les maths.
- Chaque tour renvoie tout l'historique (cours joints compris) ; le cache de préfixe réduit fortement le coût, mais un gros PDF pèse quand même sur la première requête.
- Le projet a été écrit sans compilateur sous la main : si Xcode ou Swift Playgrounds signale une erreur, elle devrait être locale et facile à corriger — ouvre une issue avec le message.
