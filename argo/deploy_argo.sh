#!/bin/bash

kustomize build --enable-helm . | kubectl apply -f -