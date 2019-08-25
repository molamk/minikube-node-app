# How to run a Node.js app with Docker, Kubernetes and Minikube

## Set up your tools

```bash
# Virtualbox (for virtualization)
brew cask install virtualbox

# HyperKit
brew install hyperkit

# Docker
brew cask install docker

# Kubernetes CLI & kubectl
brew install kubernetes-cli

# Minikube => Local Kubernetes
brew cask install minikube

# Helm => Chart management (optional)
brew install kubernetes-helm
```

## Writing a (minimal) Node.js app

We won't dive into the details of how to write a good Node.js app in this tutorial. Our app will have a minimal server with only one route and one method, namely `GET /`. Of course we can add as much features as we want, but for the purposes of this tutorial, we'll focus more on infrastructure with Docker, Kubernetes and Minikube. Here's what our app will look like:

```js'
const express = require('express');

// Constants
const PORT = process.env.PORT || 3000;
const HOST = '0.0.0.0'

// App
const app = express();
app.get('/', (req, res) => {
    res.send('Hello world\n');
});

app.listen(PORT, HOST);
console.log(`Running on http://${HOST}:${PORT}`);
```

We only need one `npm` package, which is `express`. To install it, run:

```bash
npm install --save express
```

## Dockerizing the app

We can dockerize our app by writing a `Dockerfile`, which is a set of steps Docker will run to bundle it. It looks like this:

```dockerFROM node:10

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./

RUN npm install
# If you are building your code for production
# RUN npm ci --only=production

# Bundle app source
COPY . .

EXPOSE 80
CMD [ "node", "index.js" ]
```

We'll also ignore some files, like the locally installed `node_modules`. To do that we create a `.dockerignore` file:

```text
node_modules
Dockerfile
.dockerignore
npm-debug.log
```

Now that we're set, we need to actually build our Docker image then run the container. Since I always forget the exact commands to do so, I prefer to put those in a `Makefile`. Here's what it can look like:

```makefile
image-name="molamk/node-app"

build:
    docker build -t $(image-name) .

run:
    docker run -p 3000:80 -d $(image-name)
```

Now we'll build the image, then run our container. It should give us `"Hello World"` response with a `200` status when we call it with `curl`.

```bash
# Build the image
make build

# Run the container
make run

# Call our API
curl -v localhost:3000

# HTTP/1.1 200 OK
# X-Powered-By: Express
# Content-Type: text/html; charset=utf-8
# Content-Length: 12
# ETag: W/"c-M6tWOb/Y57lesdjQuHeB1P/qTV0"
# Date: Sat, 24 Aug 2019 21:00:43 GMT
# Connection: keep-alive

# Hello world
```

Cool! Now that our app is dockerized, we can tag & push the image to [Dockerhub](https://hub.docker.com). We'll add some stuff to our `makefile` to do that:

```makefile
tag:
    docker tag molamk/node-app molamk/node-app:latest

push:
    docker push molamk/node-app
```

## Local Kubernetes with Helm & Minikube

We'll use Helm to bundle our application as a package, ready to be deployed on Kubernetes. Here's a little more info about Helm:

>"Helm helps you manage Kubernetes applications — Helm Charts help you define, install, and upgrade even the most complex Kubernetes application.
Charts are easy to create, version, share, and publish — so start using Helm and stop the copy-and-paste." - [The Helm Team](https://helm.sh)

First we need to initialize Helm, here's how we do that

```bash
# Fire up Minikube
minikube start
minikube addons enable ingress

# Initialization
helm init

# Update the repositories to their latest versions
helm repo update
```

After that we create what's called a Chart which will contain the manifest files for our Kubernetes deployment and service.

```bash
helm create node-app
```

Now let's go into the chart generated folder `node-app` and edit some `yaml`. We'll set the repository to be our own Docker image that we pushed previously.

```yaml
# Chart.yaml

apiVersion: v1
appVersion: "1.0"
description: Running a Node.js app with Docker, Kubernetes and Minikube
name: node-app
version: 0.1.0
```

```yaml
# values.yaml

replicaCount: 1

image:
  repository: molamk/node-app
  tag: latest
  pullPolicy: Always

env:
  containerPort: "80"

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: true
  annotations: {}
  hosts:
    - host: minikube-node-app.local
      paths: ["/"]

  tls: []

resources: {}

nodeSelector: {}

tolerations: []

affinity: {}
```

We'll also modify the `deployment.yaml` file a little bit to infer our custom port.

```yaml
# deployment.yaml

apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "node-app.fullname" . }}
  labels:
{{ include "node-app.labels" . | indent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ include "node-app.name" . }}
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "node-app.name" . }}
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
    {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
    {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: "PORT"
              value: "{{ .Values.env.containerPort }}"
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /
              port: http
          readinessProbe:
            httpGet:
              path: /
              port: http
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
    {{- end }}
    {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
    {{- end }}
```

Now let's deploy that on Kubernetes. We'll use the Helm CLI to do so, then we'll verify that everything is set up correctly.

```bash
# Deploy
helm install node-app

# Verify that it's been set-up
helm ls

# NAME                    REVISION        UPDATED                         STATUS          CHART           APP VERSION     NAMESPACE
# wondering-cricket       1               Sun Aug 25 18:24:51 2019        DEPLOYED        node-app-0.1.0  1.0             default
```

## Testing the whole set-up

Now let's tell our `/etc/hosts` file about our custom host `minikube-node-app.local` so we can call our endpoint. We'll the call it with `curl` which should return a *Hello world* response with a *200* status code.

```bash
# Putting our custom host into the host file
echo "$(minikube ip) minikube-node-app.local" | sudo tee -a /etc/hosts

# Calling our endpoint
curl -i minikube-node-app.local

# HTTP/1.1 200 OK
# X-Powered-By: Express
# Content-Type: text/html; charset=utf-8
# Content-Length: 12
# ETag: W/"c-M6tWOb/Y57lesdjQuHeB1P/qTV0"
# Date: Sat, 24 Aug 2019 21:00:43 GMT
# Connection: keep-alive

# Hello world
```

## Read the article

[Running A Node.Js App With Docker, Kubernetes And Minikube](https://molamk.com/minikube)
