#!/bin/bash.sh

argocd app create apps \
    --dest-namespace argo \
    --dest-server https://kubernetes.default.svc \
    --repo git@github.com:NickMoignard/homelab.git \
    --path argocd-apps;
argocd app sync apps;

argocd app sync -l app.kubernetes.io/instance=apps;
