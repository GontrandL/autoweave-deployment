# Guide de dépannage Memgraph - "Executable not found"

## Problème identifié

L'erreur "exec: 'memgraph': executable file not found in $PATH" indique que le conteneur ne trouve pas l'exécutable Memgraph à l'emplacement spécifié.

## Solutions disponibles

### 1. Utiliser l'entrypoint par défaut (memgraph.yaml)

J'ai modifié le fichier principal pour ne pas spécifier de commande :
```yaml
# Pas de "command:", utilise l'entrypoint de l'image
args: [
  "--log-level=INFO",
  "--also-log-to-stderr",
  "--telemetry-enabled=false"
]
```

**Déployer :**
```bash
kubectl delete statefulset memgraph -n autoweave-memory
kubectl apply -f k8s/memory/memgraph.yaml
```

### 2. Pod de débogage (memgraph-debug.yaml)

Pour investiguer où se trouve l'exécutable :
```bash
kubectl apply -f k8s/memory/memgraph-debug.yaml
kubectl logs memgraph-debug -n autoweave-memory

# Ou entrer dans le pod
kubectl exec -it memgraph-debug -n autoweave-memory -- bash
```

### 3. Script d'entrypoint personnalisé (memgraph-entrypoint.yaml)

Cette version cherche automatiquement l'exécutable :
```bash
kubectl delete statefulset memgraph -n autoweave-memory
kubectl apply -f k8s/memory/memgraph-entrypoint.yaml
```

### 4. Image Memgraph-MAGE (memgraph-mage.yaml)

Version alternative avec plus d'outils inclus :
```bash
kubectl delete statefulset memgraph -n autoweave-memory
kubectl apply -f k8s/memory/memgraph-mage.yaml
```

### 5. Version minimale (memgraph-minimal.yaml)

Déjà créée, utilise un Deployment avec mode fallback.

## Ordre de test recommandé

1. **D'abord** : Essayer la version principale corrigée
   ```bash
   kubectl apply -f k8s/memory/memgraph.yaml
   kubectl logs memgraph-0 -n autoweave-memory -f
   ```

2. **Si échec** : Utiliser le pod de débogage pour comprendre
   ```bash
   kubectl apply -f k8s/memory/memgraph-debug.yaml
   kubectl logs memgraph-debug -n autoweave-memory
   ```

3. **Ensuite** : Essayer memgraph-mage.yaml (image différente)
   ```bash
   kubectl apply -f k8s/memory/memgraph-mage.yaml
   ```

4. **Alternative** : Utiliser memgraph-entrypoint.yaml (recherche auto)
   ```bash
   kubectl apply -f k8s/memory/memgraph-entrypoint.yaml
   ```

## Commandes de diagnostic

```bash
# Voir l'état actuel
kubectl get pods -n autoweave-memory

# Décrire le pod pour voir les événements
kubectl describe pod memgraph-0 -n autoweave-memory

# Voir les logs complets
kubectl logs memgraph-0 -n autoweave-memory --previous

# Entrer dans un pod qui fonctionne
kubectl run -it --rm debug --image=memgraph/memgraph:2.11.1 --restart=Never -n autoweave-memory -- bash

# Vérifier l'image localement avec Docker
docker run --rm -it memgraph/memgraph:2.11.1 bash -c "which memgraph || find / -name memgraph 2>/dev/null"
```

## Solution de contournement Docker

Si aucune solution Kubernetes ne fonctionne :
```bash
# Arrêter le pod K8s
kubectl delete statefulset memgraph -n autoweave-memory

# Lancer avec Docker directement
docker run -d \
  --name memgraph \
  --network host \
  -v memgraph_data:/var/lib/memgraph \
  -e MEMGRAPH_USER=memgraph \
  -e MEMGRAPH_PASSWORD=autoweave \
  memgraph/memgraph:2.11.1

# Vérifier
docker logs memgraph
```

## Notes importantes

1. L'image `memgraph/memgraph:latest` peut avoir des changements non documentés
2. La version `2.11.1` est plus stable
3. L'image `memgraph-mage` inclut des algorithmes supplémentaires
4. Le problème peut être spécifique à l'architecture CPU (ARM vs x86)

## Vérification finale

Une fois Memgraph démarré :
```bash
# Test de connexion
echo 'RETURN "Hello from Memgraph";' | kubectl exec -i memgraph-0 -n autoweave-memory -- mgconsole
```