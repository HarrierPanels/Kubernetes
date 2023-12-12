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
    volumeID: "vol-03af749d82c847c5d"
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
          # Install CRUD
          curl -L -o /tmp/crud.zip https://github.com/FaztWeb/php-mysql-crud/archive/master.zip
          unzip /tmp/crud.zip -d /tmp/
          cp -rv /tmp/php-mysql-crud-master/* /usr/share/nginx/html/
          rm -rf /tmp/crud.zip /tmp/php-mysql-crud-master

          cd /usr/share/nginx/html/
          # Modify the SQL script
          sed -i "s/php_mysql_crud/'"$dbname"'/g" database/script.sql
          sed -i 's/CREATE DATABASE/CREATE DATABASE IF NOT EXISTS/' database/script.sql
          sed -i 's/CREATE TABLE/CREATE TABLE IF NOT EXISTS/' database/script.sql
          # Execute the SQL script with dynamic variables
          mysql -h "$DB_HOSTNAME" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "source /var/www/html/database/script.sql"

          # Modify PHP files
          sed -i "s/php_mysql_crud/'"$dbname"'/g" db.php
          sed -i "s/root/'"$username"'/g" db.php
          sed -i "s/password123/'"$password"'/g" db.php
          sed -i "s/localhost/'"$DB_HOSTNAME"'/g" db.php
          sed -i 's/erro/error/' db.php
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

