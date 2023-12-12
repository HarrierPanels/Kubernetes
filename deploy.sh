#!/bin/bash

# Set your variables
username="username"
password="password"
dbname="dbname"

# Create Kubernetes manifests using heredocs

# Namespace for CRUD
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: crud-namespace
EOF

# Namespace for Database
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: db-namespace
EOF

# Secrets for closed repository
kubectl create secret generic repo-secrets \
  --namespace=crud-namespace \
  --from-literal=username="$username" \
  --from-literal=password="$password" \
  --from-literal=dbname="$dbname" \
  --dry-run=client -o yaml | kubectl apply -f -

# ConfigMap for environment variables
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: crud-configmap
  namespace: crud-namespace
data:
  DatabaseName: "$dbname"
  DatabaseHostName: "db-service.db-namespace.svc.cluster.local"
  DatabaseUsername: "$username"
  DatabasePassword: "$password"
  ALBDNSName: "lb-service.elb.amazonaws.com"
EOF

# Database Deployment, Service, and PersistentVolume for MySQL (Example)
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: db-deployment
  namespace: db-namespace
  labels:
    app: db
spec:
  replicas: 1
  selector:
    matchLabels:
      app: db
  template:
    metadata:
      labels:
        app: db
    spec:
      containers:
      - name: mysql-container
        image: mysql:latest
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: repo-secrets
              key: password
        - name: MYSQL_DATABASE
          valueFrom:
            secretKeyRef:
              name: repo-secrets
              key: dbname
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: repo-secrets
              key: username
        - name: MYSQL_PASSWORD
          valueFrom:
            secretKeyRef:
              name: repo-secrets
              key: password
        ports:
        - containerPort: 3306
---
apiVersion: v1
kind: Service
metadata:
  name: db-service
  namespace: db-namespace
spec:
  selector:
    app: db
  ports:
    - protocol: TCP
      port: 3306
      targetPort: 3306
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: db-pv
  namespace: db-namespace
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  awsElasticBlockStore:
    volumeID: "<your-EBS-volume-id>"
    fsType: ext4
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-pvc
  namespace: db-namespace
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  selector:
    matchLabels:
      app: db
---
# Add other necessary configurations for your specific database setup...
EOF

# CRUD Deployment with Init Container
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crud-deployment
  namespace: crud-namespace
  labels:
    app: crud
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crud
  template:
    metadata:
      labels:
        app: crud
    spec:
      initContainers:
      - name: init-container
        image: alpine:latest
        command: ['sh', '-c', '
          # Your init container commands here
          ']
      containers:
      - name: nginx-php-container
        image: <your-nginx-php-image>
        ports:
        - containerPort: 80
      # Other container configurations...
---
apiVersion: v1
kind: Service
metadata:
  name: crud-service
  namespace: crud-namespace
spec:
  selector:
    app: crud
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
# Add other necessary manifests like Ingress, PVC, etc.
EOF

