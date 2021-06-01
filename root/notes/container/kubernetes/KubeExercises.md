# K8s Exercises

___

Exercises from courses

* Run a Job
* Deploy a Pod
* Create the service
* Explore the Sandbox
* Deployments - Rollout
* Setting Container Environment Variables
* Scaling Practice
* Label ALL THE THINGS!
* Raise a DaemonSet
* Replication Controllers, Replica Sets, and Deployments
* Label a Node & Schedule a Pod
* Multiple Schedulers
* View The Logs
* Maintenance on Node 3!
* Cluster DNS & Service Discovery



## Run a Job
 
Applications that run to completion inside a pod are called "jobs."  This is useful for doing batch processing.

Most Kubernetes objects are created using yaml. Here is some sample yaml for a job which uses perl to calculate pi to 2000 digits and then stops.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  template:
    spec:
      containers:
      - name: pi
        image: perl
        command: ["perl",  "-Mbignum=bpi", "-wle", "print bpi(2000)"]
      restartPolicy: Never
  backoffLimit: 4
```

Create this yaml file on your master node and call it "pi-job.yaml". Run the job with the command:

```bash
kubectl create -f pi-job.yaml
```

1. Check the status of the job using the `kubectl describe jobs` command.
2. When the job is complete, view the results by using the `kubectl logs <JOB_NAME>` command on the appropriate pod.
3. Write yaml for a new job.  Use the image "busybox" and have it sleep for 10 seconds and then complete.  Run your job to be sure it works.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: sleep
spec:
  template:
    spec:
      containers:
      - name: sleep
        image: busybox
        command: ["sleep", "10"]
      restartPolicy: Never
  backoffLimit: 4
```
* Commands
```bash
kubectl create -f job-sleep.yml 
kubectl describe jobs
kubectl get pods
kubectl get pods --show-all
kubectl logs sleep-wht9w
kubectl describe jobs
kubectl delete jobs sleep
```

## Deploy a Pod

Pods usually represent running applications in a Kubernetes cluster.  Here is an example of some yaml which defines a pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: alpine
  namespace: default
spec:
  containers:
  - name: alpine
    image: alpine
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always

```
1. Looking at the yaml, describe what the pod will do.
2. Run the pod.
3. Delete the pod.

```bash
kubectl create -f pod-alpine.yaml
kubectl get pods
kubectl desccribe pods
```

4. Write yaml for a pod that runs the nginx image.
5. Run your yaml to ensure it functions as expected.


```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
spec:
  containers:
    - name: nginx
      image: nginx
  restartPolicy: Always
```

```bash
kubectl create -f nginx-pod.yaml
kubectl get pods
```

Delete any user pods you created during this exercise.

```bash
kubectl delete -f pod-alpine.yaml
kubectl delete pod nginx-prod
kubectl delete pod/nginx-prod
```

## Create the service

* Setup

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  labels:
    app: nginx-service
spec:
  ports:
    - port: 8000
      targetPort: 80
      protocol: TCP
  selector:
    app: nginx

```


```bash
kubectl create -f service-nginx.yaml
```

* Check

```bash
kubectl get services
kubectl describe service nginx-service
```

* Test

```bash
kubectl run busybox --generator=run-pod/v1 --image=busybox --restart=Never --tty -i
wget -qO- http://10.111.20.191:8000
```



## Explore the Sandbox

* **Description**

1. Examine the current status of your cluster. Are all the nodes ready? How do you know?
2. Are there any pods running on node 2 of your cluster? How can you tell?
3. Is the master node low on memory currently? How can you tell?
4. What pods are running in the kube-system namespace? What command did you use to find out?

* **Answers**

1. The command kubectl get nodes will give the current status of all nodes.
2. You can get this information in a variety of ways:
* kubectl describe node node-name
* kubectl get pods --all-namespaces -o wide will list all pods and which nodes they are currently running on.
3. kubectl describe node node-2-name will list DiskPressure and MemoryPressure statuses so you can see how it is doing.
4. kubectl get pods -n kube-system will provide the desired results.


## Deployments - Rollout

* **Description**

Here is some yaml for an nginx deployment:

```yaml
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2 
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.7.9
        ports:
        - containerPort: 80
```

1. Create the deployment.
2. Which nodes are the pods running on. How can you tell?
3. Update the deployment to use the 1.8 version of the nginx container and roll it out.
4. Update the deployment to use the 1.9.1 version of the nginx container and roll it out.
5. Roll back the deployment to the 1.8 version of the container.
6. Remove the deployment

* **Answer**

1. Create the yaml file and name it something. I chose `nginx-deployment.yaml`. Create the deployment object by calling `kubectl create -f nginx-deployment.yaml`.
2. You can find this answer by doing a `kubectl describe deployment nginx-deployment`.
3. There are many ways to get this:
* `kubectl get pods -l app=nginx -o wide` gives you the results in one step and uses a label selector.
Or, you could:
* `kubectl describe deployment nginx-deployment` to get the pod information about the deployment and, using that,
`kubectl get pods name-of-pods -o wide`

4. There are many ways. Here are two:
* `kubectl set image deployment nginx-deployment nginx=nginx:1.8`. This will work just fine but is not the preferred method because now the yaml is inconsistent with what you've got running in the cluster. Anyone coming across your yaml will assume it's what is up and running and it isn't.
* Update the line in the yaml to the 1.8 version of the image, and apply the changes with `kubectl apply -f nginx-deployment.yaml`
5. Same as above. Don't forget you can watch the status of the rollout with the command `kubectl rollout status deployment nginx-deployment`.

6. `kubectl rollout undo deployment nginx-deployment` will undo the previous rollout, or if you want to go to a specific point in history, you can view the history with `kubectl rollout history deployment nginx-deployment` and roll back to a specific state with `kubectl rollout history deployment nginx-deployment --revision=x`.

## Setting Container Environment Variables

* **Description**

1. Write yaml for a job that will run the busybox image and will print out its environment variables and shut down.
2. Add the following environment variables to the pod definition:
```
STUDENT_NAME="Your Name"
SCHOOL="Linux Academy"
KUBERNETES="is awesome"
```
3. Run the job.
4. Verify that the environment variables were added.

* **Answer**

1. There are lots of possibilities, but here is what I came up with:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-dump
spec:
  containers:
  - name: busybox
    image: busybox
    command:
      - env
```
2. Change the yaml to something like this:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-dump
spec:
  containers:
  - name: busybox
    image: busybox
    command:
      - env
    env:
    - name: STUDENT_NAME
      value: "Your Name"
    - name: SCHOOL
      value: "Linux Academy"
    - name: KUBERNETES
      value: "is awesome"
```
3. kubectl create -f env-dump.yaml and wait for the pod to return the status of "Completed."
4. kubectl logs env-dump will show all the environment variables.

## Scaling Practice

* **Description**

Consider this YAML for an nginx deployment:

```yaml
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 2 
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
```

Complete and answer the following:

1. Scale the deployment up to 4 pods without editing the YAML.
1. Edit the YAML so that 3 pods are available and can apply the changes to the existing deployment.
1. Which of these methods do you think is preferred and why?

* **Answers**

To scale the deployment up to 4 pods, use: `kubectl scale deployment nginx-deployment --replicas=4`

To make it so 3 pods can be available and apply the changes to the existing deployment, complete the following:

1. Edit the YAML as follows:
```yaml
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  selector:
    matchLabels:
      app: nginx
  replicas: 3
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
```
2. Execute the command: `kubectl -f apply nginx-deployment `

Performing the edit in the YAML is the preferred one, as it keeps the YAML on disk in sync with the state of the cluster.


## Label ALL THE THINGS!


* **Description**

Putting labels on objects in Kubernetes allow you to identify and select objects in as wide or granular style as you like.

1. Label each of your nodes with a "color" tag. The master should be black; node 2 should be red; node 3 should be green and node 4 should be blue.
2. If you have pods already running in your cluster in the default namespace, label them with the key/value pair running=beforeLabels.
3. Create a new alpine deployment that sleeps for one minute and is then restarted from a yaml file that you write that labels these container with the key/value pair running=afterLabels.
4. List all running pods in the default namespace that have the key/value pair running=beforeLabels.
5. Label all pods in the default namespace with the key/value pair tier=linuxAcademyCloud.
6. List all pods in the default namespace with the key/value pair running=afterLabels and tier=linuxAcademyCloud.

* **Answers**

1.

* `kubectl label node node1-name color=black` for the master.
* `kubectl label node node2-name color=red` for node 2.
* `kubectl label node node3-name color=green` for node 3.
* `kubectl label node node4-name color=blue` for node 4.

2. `kubectl label pods -n default running=beforeLabels --all`

3. create `alpine-label.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: alpine
  namespace: default
  labels:
    running: afterLabels
spec:
  containers:
  - name: alpine
    image: alpine
    command:
      - sleep
      - "60"
  restartPolicy: Always
```

4. `kubectl get pods -l running=beforeLabels -n default`
5. `kubectl label pods --all -n default tier=linuxAcademyCloud`
6. `kubectl get pods -l running=afterLabels -l tier=linuxAcademyCloud`


## Raise a DaemonSet


* **Description**

No black magic is required, just a bit of yaml.

Write the yaml to deploy a DaemonSet (just use an nginx image) and then test it to be sure it gets deployed on each node.  Delete the pods when you've completed this exorcism.  Er... Exercise.


* **Answers**

There are lots of possible solutions to this exercise, but here is what I came up with:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cthulu
  labels:
    daemon: "yup"
spec:
  selector:
    matchLabels:
      daemon: "pod"
  template:
    metadata:
      labels:
        daemon: pod
    spec:
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: cthulu-jr
        image: nginx
```

## Label a Node & Schedule a Pod

* **Description**

1. Pretend that node 3 is your favorite node.  Maybe it's got all SSDs.  Maybe it's got a fast network or a GPU.  Or maybe it sent you a nice tweet.  Label this node in some way so that you can schedule a pod to it.
2. Create a yaml for a busybox sleeper/restarter that will get scheduled to your favorite node from #1.


* **Answers**

There are many possible answers to this exercise, here is what I came up with:

1. To mark my favorite node, I used `kubectl label node node3-name myDarling=bestOne`.
2. For my pod to be launched on my favorite node, I used this yaml:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: default
spec:
  containers:
  - name: busybox
    image: busybox
    command:
      - sleep
      - "300"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
  nodeSelector: 
    myDarling: bestOne

```

## Multiple Schedulers

* **Description**

Pods generally are scheduled by the default scheduler, and their yaml might look like this:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: annotation-default-scheduler
  labels:
    name: multischeduler
spec:
  schedulerName: default-scheduler
  containers:
  - name: pod-container
    image: k8s.gcr.io/pause:2.0
```

Ordinarily, we don't need to specify the scheduler's name in the spec because everyone uses a single default one. Sometimes, however, developers need to have custom schedulers in charge of placing pods due to legacy or specialized hardware constraints.

Rewrite the yaml for this pod so it makes use of a scheduler called custom-scheduler, and annotate the pod accordingly.


* **Answers**

```yaml

apiVersion: v1
kind: Pod
metadata:
  name: annotation-default-scheduler
  labels:
    name: multischeduler
  annotations:
    scheduledBy: custom-scheduler
spec:
  schedulerName: custom-scheduler
  containers:
  - name: pod-container
    image: k8s.gcr.io/pause:2.0
    
```

## Replication Controllers, Replica Sets, and Deployments

* **Description**

Deployments replaced the older ReplicationController functionality, but it never hurts to know where you came from.  Deployments are easier to work with, and here's a brief exercise to show you how.

A Replication Controller ensures that a specified number of pod replicas are running at any one time. In other words, a Replication Controller makes sure that a pod or a homogeneous set of pods is always up and available.

1. **Write a YAML file that will create a Replication Controller that will maintain three copies of an nginx container.  Execute your YAML and make sure it works.**

> A Replica Set is a more advanced version of a Replication Controller that is used when more low-level control is needed.  While these are commonly managed with deployments in modern K8s, it's good to have experience with them.

2. **Write the YAML that will maintain three copies of an nginx container using a Replica Set.  Test it to be sure it works, then delete it.**

> A deployment is used to manage Replica Sets.  

3. **Write the YAML for a deployment that will maintain three copies of an nginx container.  Test it to be sure it works, then delete it.**

* **Answers**

To create the replication controller, write the following YAML file:

Replication Controller:

```yaml
apiVersion: v1
kind: ReplicationController
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    app: nginx
  template:
    metadata:
      name: nginx
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
```

To maintain three copies of an nginx container in a replica set, write the following YAML file: 

Replication Set:

```yaml
apiVersion: apps/v1beta2
kind: ReplicaSet
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
```

To perform a deployment for the Replica Set, write the following YAML file:

Deployment:

```yaml
apiVersion: apps/v1beta2 # for versions before 1.8.0 use apps/v1beta1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        ports:
        - containerPort: 80
```

## View The Logs

* **Description**

Create this object in your cluster:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: counter
  labels:
    demo: logger
spec:
  containers:
  - name: count
    image: busybox
    args: [/bin/sh, -c, 'i=0; while true; do echo "$i: $(date)"; i=$((i+1)); sleep 3; done']
```
This is a small container which wakes up every three seconds and logs the date and a count to stdout.

1. View the current logs of the counter.
2. Allow the container to run for a few minutes while viewing the log interactively.
3. Have the command only print the last 10 lines of the log.
4. Look at the logs for the scheduler. Have there been any problems lately that you can see?
5. Kubernetes uses etcd for its key-value store. Take a look at its logs and see if it has had any problems lately.
6. Kubernetes API server also runs as a pod in the cluster. Find and examine its logs.

* **Answers**

1. `kubectl logs counter`
2. `kubectl logs counter -f`
3. `kubectl logs counter --tail=10` or, since `--tail` defaults to 10, just `kubectl logs counter --tail`
4. This question really wants to know if you can find the logs for the scheduler. They're in the master in the `/var/log/containers` directory. There, a symlink has been create to the appropriate container's log file, and the symlink will have a name that begins with "kube-scheduler-" These logs belong to root, so you will have to sudo to view them.
5. The etcd logs are in the same directory as the logs for the previous question, only the name of the symlink begins with "etcd-", and also belongs to root.
6. The API server also lives in the same directory and begins with "kube-apiserver-", and also belongs to root.

## Maintenance on Node 3!

* **Description**

Node 3 (Hey, isn't that your favorite node?) needs to have some maintenance done on it. The ionic defibulizer needs a new multiverse battery and the guys in the data center are impatient to get started.

1. Prepare node 3 for maintenance by preventing the scheduler from putting new pods on to it and evicting any existing pods. Ignore the DaemonSets -- those pods are only providing services to other local pods and will come back up when the node comes back up.

2. When you think you've done everything correctly, go to the Cloud Servers page and shut node 3 down. Don't delete it! Just stop it. While it's down, we'll pretend that it's getting that new multiverse battery. While you wait for the cluster to stabilize, practice your yaml writing skills by creating yaml for a new deployment that will run six replicas of an image called k8s.gcr.io/pause:2.0. Name this deployment "lots-of-nothing".

3. Bring the "lots-of-nothing" deployment up on your currently 75% active cluster. Notice where the pods land.

4. Imagine you just got a text message from the server maintenance crew saying that the installation is complete. Go back to the Cloud Server tab and start Node 3 up again. Fiddle with your phone and send someone a text message if it helps with the realism.  Once Node 3 is back up and running and showing a "Ready" status, allow the scheduler to use it again.

5. Did any of your pods move to take advantage of the additional power?  You get 143 bonus points for this exercise if you know what an ionic defibulizer is.  Tweet the answer to me @OpenChad.  Use the hashtag #NoYouDontReallyGetPoints.


* **Answers**

1. `kubectl drain node3-name --ignore-daemonsets`

2. Again, there are lots of possible answers, but here's one that I wrote:

```yaml
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: lots-of-nothing
spec:
  selector:
    matchLabels:
      timeToGet: schwifty
  replicas: 6
  template:
    metadata:
      labels:
        timeToGet: schwifty
    spec:
      containers:
      - name: pickle-rick
        image: k8s.gcr.io/pause:2.0
```

3. `kubectl create -f lots-of-nothing.yaml` will bring it up if you named the yaml the same way I did. If you set up your labels like I did, then the command to show you where all the pods wound up is `kubectl get pods -o wide -l timeToGet=schwifty`. My point here is beyond just being a little silly -- your labels can be whatever you want them to, so it makes a lot of sense to think through some conventions and standards with your colleagues and other users of your cluster, otherwise you will end up with nonsensical labels like mine.

4.`kubectl uncordon node3-name` will allow the scheduler to once again allow pods to be scheduled on the node.

5. No, the uncordon only affects pods being scheduled and won't move any back unless other nodes are experiencing MemoryPressure or DiskPressure.


## Cluster DNS & Service Discovery

* **Description**

In a Kubernetes cluster, services discover one another through the Cluster DNS.  Names of services resolve to their ClusterIP, allowing application developers to only know the name of the service deployed in the cluster and not have to figure out how to get all the right IP addresses into the right containers at deploy time.

Here is yaml for a deployment:
```yaml
apiVersion: apps/v1beta2
kind: Deployment
metadata:
  name: bit-of-nothing
spec:
  selector:
    matchLabels:
      app: pause
  replicas: 2
  template:
    metadata:
      labels:
        app: pause
    spec:
      containers:
      - name: bitty
        image: k8s.gcr.io/pause:2.0
```

Create this file and name it `bit-of-nothing.yaml`.

1. Run the deployment and verify that the pods have started.

2. Start a busybox pod you can use to check DNS resolution (you can use my yaml, below, if you like, but it's good practice to write your own!)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: busybox
  namespace: default
spec:
  containers:
  - name: busybox
    image: busybox
    command:
      - sleep
      - "3600"
    imagePullPolicy: IfNotPresent
  restartPolicy: Always
```

3. Check to see whether or not bit-of-nothing is currently being resolved in the cluster via your busybox container.
4. Expose the bit-of-nothing deployment as a ClusterIP service.
5. Verify that "bit-of-nothing" is now being resolved to an IP address in your cluster.

* **Answers**

1. `kubectl create -f bit-of-nothing.yaml` At this point, this command should be second nature to you, unless you're doing a lot of skipping around.
2. `kubectl create -f busybox.yaml`
3. `kubectl exec -it busybox -- nslookup bit-of-nothing` should error out with not found.
4. `kubectl expose deployment bit-of-nothing --type=ClusterIP --port 80`
5. `kubectl exec -it busybox -- nslookup bit-of-nothing` should return an IP address after a few moments.

