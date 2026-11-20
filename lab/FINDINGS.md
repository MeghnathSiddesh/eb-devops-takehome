# Findings — Part 4 debug lab

Fill in one entry per defect you find. Paste the *actual* output you saw —
we cross-check it against your session recording and your git diff, and the
diagnostic path matters more to us than the fix itself.

Before you start investigating, begin recording:
`script -q part4-session.log` (or `asciinema rec part4-session.cast`), and
commit that file alongside this one.

---

## Defect 1

**Symptom** scenario.sh scrip failed due to error for object debug-lab/migrate :
Error: server-side apply failed for object debug-lab/migrate batch/v1, Kind=Job: Job.batch "migrate" is invalid: spec.template.spec.restartPolicy: Required value: valid values: "OnFailure", "Never"

**Cause** : the Job object was set to restartPolicy: Always, this will restart the pod even if it terminated gracefully with zero exit code
            but the objective of Job is terminate once the job is completed successfully

**Fix** : set restartPolicy: OnFailure

**How I found it** (the sequence of commands/reasoning that led you here):
./scenario.sh up, command gave error which points to restartpolicy in kubernetes Job object which is set to Always, it should be either OnFailure or never

---

## Defect 2

**Symptom:** Error container has runAsNonRoot and image has non-numeric user (nonroot), cannot verify user is non-root (pod: "gateway-5cbdcd4bf8-4gq4n_debug-lab

**Cause:** The error occurs because you must explicitly set a numeric runAsUser in securityContext for both your backend deployment and your gateway deployment.
Your container image defines its default user as a string (USER nonroot). When runAsNonRoot: true is enabled, Kubernetes refuses to start the container without a numeric UID because it cannot verify at runtime whether the text name "nonroot" maps to UID 0 (root) inside the image.

**Fix:** Add runAsUser which is runAsUser: 10001

**How I found it:**
 kubectl describe pod gateway-5cbdcd4bf8-4gq4n -n debug-lab
 when describing the pod, i found kubernetes try to run these pods as user nonroot but container accepts accepts UID
---

## Defect 3

**Symptom:** Readiness probe failed: Get "http://10.244.0.20:8080/healthz": dial tcp 10.244.0.20:8080: connect: connection refused
we got readinesprobe error, so i have checked if the container lisetning on that port

**Cause:** The image docker.io/ebinterview/eb-debug-app sets the application to listen on port 8081, however it was configured that all the running with this images must receive traffic on 8080

**Fix:** i have updated the common.port to 8081 in values.yaml and upgraded the helm release
 helm upgrade debug-lab ./broken-chart -n debug-lab


**How I found it:**  kubectl logs gateway-6c78fd6c6f-cfsn9 -n debug-lab
2026/11/20 19:17:06 eb-debug-app 2.0.0 starting: mode=gateway pod=gateway-6c78fd6c6f-cfsn9 listening on :8081 (image default is 8081; set PORT to override)
it says the application is listening on 8081

---

## Defect 4

**Symptom:** ServiceAccount debug-lab/reporter cannot list pods

**Cause:** the RoleBinding when attaching role to a  Serviceaccount, it is refferring default role

**Fix:** i have updated it to, name: reporter

**How I found it:** i was getting error that role reporter cannot list pods, so when i checked the role it writted correct, however the Rolebinding needs to be corrected

---

## Defect 5

**Symptom:**  FATAL: worker could not initialise its cache: mkdir /var/cache/app: read-only file system — the process needs a writable directory at /var/cache/app (mount a volume there, or set CACHE_DIR)

worker pods: The application is trying to create a directory at /var/cache/app at startup. However, in worker.yaml template,it was  configured the container with a strict security lockdown rule: readOnlyRootFilesystem: true. This locks the container's entire file system, preventing any write actions or folder creation, which causes the application to fail immediately with an Exit Code 1.

**Cause:** worker pods: The application is trying to create a directory at /var/cache/app at startup. However, in worker.yaml template,it was  configured the container with a strict security lockdown rule: readOnlyRootFilesystem: true. This locks the container's entire file system, preventing any write actions or folder creation, which causes the application to fail immediately with an Exit Code 1.


**Fix:** Disable the Read-Only Filesystem Restriction

readOnlyRootFilesystem: false
#we have other options to explore, for time being im going with this option

**How I found it:**
 kubectl logs worker-648bddc865-4jbb7 -n debug-lab
 2026/11/20 20:22:57 FATAL: worker could not initialise its cache: mkdir /var/cache/app: read-only file system — the process needs a writable directory at /var/cache/app (mount a volume there, or set CACHE_DIR)
i observed the pod logs and got to know the container is unable to write anything to directory

other approach is 

Mount an emptyDir Volume
This is the cleanest approach because it keeps  cluster secure while instantly granting the application a completely isolated, writable space at that exact path. An emptyDir automatically inherits the permissions of the user running the pod (10001).

---

## Defect 6

**Symptom:** Reporter pod remained Running but Not Ready; /healthz returned 503 due to pod-list parsing failures.

**Cause:** Root cause not conclusively identified.

i could not eastablish a proper cause for this, but i have checked from both worker pods end and from apiserver end
i have created temporary pods and tried connecting to apiserver for list pods, it was working fine 
but im unable to find what is the cause for this

**Fix:** Verified Kubernetes API connectivity from worker nodes and tested pod listing using temporary pods. API communication worked successfully; further investigation required.

**How I found it:** Checked reporter logs, pod status, health checks, and Kubernetes API connectivity using kubectl and temporary test pods.

---

