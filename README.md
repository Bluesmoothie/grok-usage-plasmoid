# Quota Grok

Widget Plasma 5 qui affiche en permanence le même quota que `/usage` dans Grok Build.

## Affichage

- **Panneau** : `Grok 77%` (vert / orange / rouge)
- **Popup** : quota global, détail Grok Build / Chat / Voice, période, date de reset
- Clic milieu sur le panneau : actualiser
- Bouton **Ouvrir /usage** : `https://grok.com/?_s=usage`

Le chiffre vient de `https://cli-chat-proxy.grok.com/v1/billing?format=credits` avec le token de `~/.grok/auth.json` — le même backend que le TUI.

## Installer

```bash
./install.sh
```

Puis : clic droit sur le panneau → **Ajouter des éléments graphiques** → **Quota Grok**.

En ligne de commande :

```bash
bin/grok-usage
```

## Notes

- Il faut une session `grok login` (pas seulement une clé API).
- Le script renouvelle le token OIDC si besoin, sous le verrou `~/.grok/auth.json.lock`.
- L’endpoint n’est pas une API publique figée : si xAI le change, le widget affichera une erreur plutôt que des chiffres faux.

## Licence

[MIT](LICENSE) © 2026 Yves Gille
