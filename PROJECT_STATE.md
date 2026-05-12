# Etat du projet stock_app

## Contexte

- Application Flutter de gestion de stock boutique.
- Cible finale: tablette Android.
- Les tests visuels actuels via Chrome/Device Preview ne representent pas la BDD Android.
- Sur Android, la BDD SQLite `stock_pilot.db` est creee au premier lancement et remplie depuis `lib/data/stock_seed.dart`.

## Points importants

- Ne pas se fier a la BDD desktop debug dans `.dart_tool/sqflite_common_ffi/databases`.
- En mode web/Chrome, l'app utilise un fallback en memoire depuis `stock_seed.dart`.
- En Android, l'app utilise `sqflite` et persiste dans la BDD interne de l'app.
- Pour tester une premiere installation propre sur tablette, desinstaller l'app avant de relancer.
- La tablette n'a pas de port USB exploitable pour une cle: le backup manuel passe par le partage Android.

## Etat fonctionnel actuel

- Categories metier par defaut:
  - `Femme`
  - `Homme`
  - `Kids`
- Gestion des categories:
  - section `Categories` ajoutee dans Reglages
  - creation de categorie
  - modification/renommage de categorie
  - suppression possible uniquement si aucun produit n'utilise la categorie
- Creation/modification produit:
  - champ emplacement supprime de l'UI
  - emplacement stocke par defaut: `Stock principal`
  - categorie via select alimente par la table SQLite `categories`
  - picker couleur reel via `flutter_colorpicker`
- Couleurs:
  - table SQLite `colors`
  - association nom couleur -> code hex
  - si `Amazonico` est associe a une couleur, toutes les variantes `Amazonico` doivent reprendre cette couleur
- Variantes:
  - ajout de variante possible depuis la fiche produit
  - modification ciblee d'une variante precise possible depuis la fiche produit
  - l'ancien probleme "ouvre toujours la premiere variante" est corrige
- References Kids:
  - format attendu: `K-RAPHAEL`
  - plus de suffixe `-KID` derriere le prenom
- Sauvegarde:
  - backups locaux automatiques conserves dans le dossier prive de l'app
  - bouton `Partager une sauvegarde` dans Reglages
  - cree une copie datee de `stock_pilot.db` puis ouvre le partage Android
  - destination possible: mobile, Bluetooth, Nearby Share, mail, Drive, etc.
  - bouton `Restaurer une sauvegarde` dans Reglages
  - selectionne un fichier `.db`, cree une copie de securite du stock actuel, remplace la BDD, puis recharge l'app

## BDD / migrations

- Fichier SQLite Android: `stock_pilot.db`, dans le stockage prive de l'app Android.
- Version BDD actuelle: `6`.
- Migrations importantes:
  - ajout `variants.color_hex`
  - ajout table `colors`
  - normalisation des references Kids
  - nettoyage categories vers `Femme`, `Homme`, `Kids`
  - les categories ne sont plus forcees a une liste fixe apres migration; elles sont lues depuis SQLite

## Verifications deja faites

- `flutter analyze`: OK
- `flutter test`: OK
- `flutter build apk --debug`: OK
- APK debug genere:
  - `build/app/outputs/flutter-apk/app-debug.apk`

## Etat seed verifie

Lors d'une creation BDD depuis zero en debug desktop:

- Produits: `97`
- Variantes: `1623`
- Pieces: `6054`
- Categories:
  - `Femme`
  - `Homme`
  - `Kids`

Note: si Chrome/Device Preview affiche autre chose, c'est probablement l'ancien etat web en memoire/cache.

## Prochaine etape

Tester sur tablette Android reelle:

1. Activer Options developpeur.
2. Activer Debogage USB.
3. Brancher la tablette.
4. Verifier:

```powershell
flutter devices
```

5. Lancer:

```powershell
flutter run
```

6. Pour tester une creation BDD propre:
   - desinstaller l'app de la tablette
   - relancer `flutter run`

## Points a tester sur tablette

- Premier lancement: BDD creee et remplie.
- Accueil: compte produits/pieces coherent avec seed.
- Creation produit.
- Modification produit.
- Ajout variante.
- Modification variante precise.
- Picker couleur:
  - association par nom
  - propagation aux variantes du meme nom
- Categories: verifier creation, renommage et suppression depuis Reglages.
- Suppression categorie: impossible si des produits l'utilisent.
- References Kids sans `-KID`.
- Suppression produit.
- Changement de stock + mouvements.
- Partage sauvegarde:
  - ouvrir Reglages
  - appuyer sur `Partager une sauvegarde`
  - verifier que la feuille de partage Android s'ouvre
  - envoyer le fichier `.db` vers le mobile
- Restauration sauvegarde:
  - recuperer un fichier `.db` sur la tablette
  - ouvrir Reglages
  - appuyer sur `Restaurer une sauvegarde`
  - choisir le fichier
  - confirmer
  - verifier que l'accueil se recharge et que les compteurs correspondent a la sauvegarde
