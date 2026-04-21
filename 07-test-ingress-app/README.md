# 07 Test Ingress App

Simple Kubernetes manifests to verify `ingress-nginx` host-based routing.

Apply with:

```bash
kubectl apply -f 07-test-ingress-app/
```

Then point `tikejhya.intra.nixbin.com` at your ingress controller IP, or test with:

```bash
curl -H 'Host: tikejhya.intra.nixbin.com' http://<INGRESS_IP>/
```
