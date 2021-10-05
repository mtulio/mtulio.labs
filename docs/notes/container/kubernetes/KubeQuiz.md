# Frequently Asqued Questions

> This is an personal study annotations for LA ([Linux Academy](https://linuxacademy.com)) courses. All credits goes to LA Inc. =]

This is FAQ from Quizes and courses

* [Core Concepts](#core-concepts)
* [Installation, Configuration and Validation](#installation-configuration-and-validation)
* Application Lifecycle Management
* Scheduling
* Networking


## Core Concepts

**1) The connection between the apiserver and nodes, pods and services:**

*Choose the correct answer:*

* Is unencrypted and therefore unsafe to run over public networks.
* Is always encrypted with IPSec.
* Is currently encrypted with IPSec with plans to allow other encryption plugins later.
* Is always encrypted using the method configured in the .kube file.

**2) Unique IP addresses are assigned to:**

*Choose the correct answer:*

* NAT is used extensively, so unique IP addresses are irrelevant
* Pods
* Container Hosts
* Containers

**3) What does a pod represent in a Kubernetes cluster?**

*Choose the correct answer:*

* A running process
* A set of rules for maintaining high availability
* Conditions under which applications will autoscale
* All the containers in the cluster

**4) Which of these are not inherently created by Kubernetes?**

*Choose the correct answer:*

* Controllers
* Services
* Pods
* Nodes


**5) What controls a Kubernetes cluster?**

*Correct answer*

* The Master
* The Pod
* The Node
* The swarm

**6)Containers are run on which of these?**

*Choose the correct answer:*

* Nodes
* None of these
* Controllers
* Services


**7) Communications between the apiserver and the kubelet on the cluster nodes are used for all but which of the following?**

*Choose the correct answer:*

* Keep-alive xml packets
* Fetching logs for pods
* Attaching (through kubectl) to running pods
* Providing the kubelet's port-forwarding capability

**8) Kubernetes changed the name of cluster members to "Nodes." What were they called before that?**

*Choose the correct answer:*

* Slaves
* Cogs
* Workers
* Minions

**9) In a typical deployment, the Kubernetes Master listens on what port number?**

*Choose the correct answer:*

* 443
* 3001
* 80
* 22

**10) Which of these is a list of common Kubernetes primitives?**

*Choose the correct answer:*

* containers, vms, hypervisors, daemons
* pod, swarm, namespace, network
* service, deployment, replicaset, etcd
* pod, service, persistentVolume, deployment

**11) Usually, when submitting a Kubernetes API call, data is sent in which format? (Select all that apply)**

*Choose the 2 correct answers:*

 - [ ] DOC
 - [ ] JSON
 - [ ] XML
 - [ ] YAML

**12) In Kubernetes, a group of one or more containers is called:**

*Choose the correct answer:*

* A pod
* A selector
* A minion
* A swarm

**13) Which of these components mount volumes to containers?**

*Choose the correct answer:*

* fluentd
* kube-scheduler
* kube-proxy
* kubelet

**14) If memory is running low on a running node, which of these keys will return "True"?**

*Choose the correct answer:*

* MemoryPressure
* Warning
* LowMemory
* OOM

**15) What is the difference between a Docker volume and a Kubernetes volume?**

*Choose the correct answer:*

* Proximity: In Docker, volumes can reside on the same host with their containers. In Kubernetes, they must reside on separate metal for resiliency.
* Back-end Drivers. Docker supports more block storage types than Kubernetes does.
* Volume lifetimes. In Docker, this is loosely defined. In Kubernetes, the volume has the same lifetime as its surrounding pod.
* Size: Docker volumes are limited to 3TB. Kubernetes volumes are limited to 16TB.

___

### Answers

**1) The connection between the apiserver and nodes, pods and services:**

*Correct answer*
Is unencrypted and therefore unsafe to run over public networks.

*Explanation*
It's a fairly simple process to encrypt the streams using TLS.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**2) Unique IP addresses are assigned to:**

*Correct answer*
Pods

*Explanation*
A pod gets assigned a single IP address, regardless of how many containers make it up. This is analogous to many services running on a single virtual machine.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**3) What does a pod represent in a Kubernetes cluster?**

*Correct answer*
A running process

*Explanation*
Pods are the running containers in a Kubernetes cluster.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**4) Which of these are not inherently created by Kubernetes?**

*Correct answer*
Nodes

*Explanation*
Nodes are added to a cluster, and a Kubernetes object is created to reflect them, but Kubernetes itself doesn't create them.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**5) What controls a Kubernetes cluster?**

*Correct answer*
The Master

*Explanation*
The master node contains the Kubernetes api server, which controls what the cluster does.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**6) Containers are run on which of these?*

*Correct answer*
Nodes

*Explanation*
Nodes run the pods.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**7) Communications between the apiserver and the kubelet on the cluster nodes are used for all but which of the following?**

*Correct answer*
Keep-alive xml packets

*Explanation*
Communications between the apiServer and the Kubelet are constantly communicating for a variety of purposes.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**8) Kubernetes changed the name of cluster members to "Nodes." What were they called before that?**

*Correct answer*
Minions

*Explanation*
A lot of documentation and tutorials online still refer to worker nodes this way.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**9) In a typical deployment, the Kubernetes Master listens on what port number?**

*Correct answer*
443

*Explanation*
The API server, by default, listens on port 443, the secure HTTP port.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**10) Which of these is a list of common Kubernetes primitives?**

*Correct answer*
pod, service, persistentVolume, deployment

*Explanation*
There are many others, but those are the ones you'll likely work with most often.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**11) Usually, when submitting a Kubernetes API call, data is sent in which format? (Select all that apply)**

*Correct answer*
JSON, YAML

*Explanation*
If using a direct API call in an application, JSON is used. If using kubectl to submit a request, it takes YAML.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**12) In Kubernetes, a group of one or more containers is called:**

*Correct answer*
A pod

*Explanation*
A pod is usually one container but can be a group of containers working together.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**13) Which of these components mount volumes to containers?**

*Correct answer*
kubelet

*Explanation*
The kubelet which runs on nodes handles moment-to-moment management of the pods on its node.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**14) If memory is running low on a running node, which of these keys will return "True"?**

*Correct answer*
MemoryPressure

*Explanation*
MemoryPressure and DiskPressure return true as a node starts to become overcommitted.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

**15) What is the difference between a Docker volume and a Kubernetes volume?**

*Correct answer*
Volume lifetimes. In Docker, this is loosely defined. In Kubernetes, the volume has the same lifetime as its surrounding pod.

*Explanation*
Docker volumes are not used in conjunction with Kubernetes at this time.

*Further Reading*
https://linuxacademy.com/cp/courses/lesson/course/1412/lesson/1/module/155

## Installtion, Configuration and Validation


**1) What is the default encryption used in Kubernetes? (Choose the answer that is most correct.)**

*Choose the correct answer:*

* HTTPS
* SSL
* TLS
* AES


**2) What is the node called that runs the apiserver?*

*Choose the correct answer:*

* The Server
* The Top
* The Client
* The Master

**3) Which of these is an inexpensive and easy way to try out Kubernetes?**

*Choose the correct answer:*

* Minikube
* Turnkey
* Manual Install
* Linux Foundation's CNI

**4) Which of these is not a CNI provider?**

*Choose the correct answer:*

* Canal
* Flannel
* Ceph
* Weave Net


**5) Which platform(s) will Minikube run on? (Select all that apply)**

*Choose the 3 correct answers:*

- [ ] Windows
- [ ] Linux
- [ ] Novell Netware v4
- [ ] Mac OS X


**6) Which types of API requests should be authenticated?**

*Choose the correct answer:*

* Node requests
* Requests from users
* All of them
* Incoming requests from proxies


**7) To deploy Kubernetes using kubeadm, you'll have to choose:**

*Choose the correct answer:*

* A passphrase for the certificates
* Between container space and swap space
* An appropriate CNI (Container Network Interface)
* The amount of RAM allocated to the Kubelets


**8) For network policies to work in Kubernetes, which of these must be true?**

*Choose the correct answer:*

* The CNI must support VxLANs.
* The CNI must enforce the network policies.
* The CNI must have a "policy" sidebar.
* Network policies are always enforced.

**9) What do many Kubernetes deployment tools handle automatically for you?**

*Choose the correct answer:*

* CNI deployment
* Certificate creation
* Kubectl installation on the master and nodes
* Custom namespaces



**10) In Kubernetes, one of the primitives is a Node (which was formerly referred to as a "Minion"). What does it represent?**

*Choose the correct answer:*

* A physical or virtual machine running the Kubelet and doing the compute work via a container service like Docker or Rocket.
* A virtual machine running the Kubelet and doing the compute work via Docker.
* A physical machine running the Kubelet and doing the compute work via a container service like Docker or Rocket.
* A virtual machine running the Kubelet and doing the compute work via a container service like Docker or Rocket.


**11) What underlying technology does Flannel use to allow pods to communicate?**

*Choose the correct answer:*

* GRE Tunnels
* IPSec Tunnels
* VxLANs
* VLANs


**12) How is authorization handled in Kubernetes?**

*Choose the correct answer:*

* LDAP/AD
* Through a variety of third-party authorization plugins.
* Through user.permission files mounted via secrets
* A built-in Role Based Access Control system.


---


**1) What is the default encryption used in Kubernetes? (Choose the answer that is most correct.)**

*Correct answer*

TLS

*Explanation*

TLS is the default encryption used in Kubernetes.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1415/lesson/1/module/155

**2) What is the node called that runs the apiserver?**

*Correct answer*

The Master

*Explanation*

The Master node runs the apiserver and is where Kubernetes accepts requests via a RESTful API.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1420/lesson/1/module/155

**3) Which of these is an inexpensive and easy way to try out Kubernetes?**

*Correct answer*

Minikube

*Explanation*

Minikube is a great and inexpensive way to try out Kubernetes.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1415/lesson/1/module/155

**4) Which of these is not a CNI provider?**

*Correct answer*

Ceph

*Explanation*

Ceph is an object store, the other three are CNI providers.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1415/lesson/1/module/155

**5) Which platform(s) will Minikube run on? (Select all that apply)**

*Correct answer*

Linux, Windows, Mac OS X

*Explanation*

And probably, just for spite, someone will port it to Novell Netware so we'll have to change this question, but Minikube should run just about anywhere.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1415/lesson/1/module/155

**6) Which types of API requests should be authenticated?**

*Correct answer*

All of them

*Explanation*

Everything, every time. Don't allow security holes in your cluster!

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1420/lesson/1/module/155

**7) To deploy Kubernetes using kubeadm, you'll have to choose:**

*Correct answer*

An appropriate CNI (Container Network Interface)

*Explanation*

kubeadm doesn't make any provisions for inter-node networking. There are a lot of CNIs to choose from!

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1415/lesson/1/module/155

**8) For network policies to work in Kubernetes, which of these must be true?**

*Correct answer*

The CNI must enforce the network policies.

*Explanation*

If the CNI doesn't support network policies, then applying a YAML formula with a network policy in it will return a success, but the policies will not be enforced.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1418/lesson/1/module/155

**9) What do many Kubernetes deployment tools handle automatically for you?**

*Correct answer*

Certificate creation

*Explanation*

Most deployment tools handle the certificate creation but will not do the other things.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1420/lesson/1/module/155

**10) In Kubernetes, one of the primitives is a Node (which was formerly referred to as a "Minion"). What does it represent?**

*Correct answer*

A physical or virtual machine running the Kubelet and doing the compute work via a container service like Docker or Rocket.

*Explanation*

While nodes are generally considered to be physical machines, as that's the norm in production deployments, they can be virtual machines as well.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1420/lesson/1/module/155

**11) What underlying technology does Flannel use to allow pods to communicate?**

*Correct answer*

VxLANs

*Explanation*

Flannel uses VxLANs for the overlay network among the pods.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1420/lesson/1/module/155

**12) How is authorization handled in Kubernetes?**

*Correct answer*

A built-in Role Based Access Control system.

*Explanation*

K8s has its own RBAC components built it.

*Further Reading*

https://linuxacademy.com/cp/courses/lesson/course/1418/lesson/1/module/155


# Quiz: Application Lifecycle Management

Is it possible to configure an application in a container from Kubernetes? If so, how is this accomplished?

Choose the correct answer:
No, this is not possible at this time but is planned for a future release.
Yes, through the use of environment variables. These can be set in the YAML file for the appropriate pod.
Yes, through the use of annotations. Annotations are key/value pairs used by the applications in the service.
Yes, through the use of Network Policies. While originally intended to be the traffic cops of the network, developers often use them "off label" to configure applications.

--

I have a deployment called "healer" running on my cluster. I look at the pods on a node and notice that there are two pods running there -- "healer-xxxxxxxx-yyyy" and "healer-xxxxxxxx-yyyz". What will happen if I issue the command "kubectl delete pod healer-xxxxxxxx-yyyz"?

Choose the correct answer:
Kubectl will issue an error message, as this pod is in use. Adding the --force flag will allow you to complete this action.
The pod will be deleted. If there is an Ingress or Service Load balancer pointing to that pod, those requests will time out.
Nothing. The pod is protected by the deployment it runs in.
The pod will be deleted, but the deployment will immediately spin up another pod to replace it, possibly on another node.


Which of these is the correct hierarchy of related Kubernetes API objects?

Choose the correct answer:
Pods make up deployments. Services point to deployments.
Pods, services, and deployments refer to the same level of hierarchy in K8s.
Services point to pods. Pods are made up of deployments.
Pods run services, which in turn are managed by deployments.

There are many ways to assign a pod to a particular node, but they all involve the use of what?

Choose the correct answer:
labels
kubectl
affinity or anti-affinity
annotations

Which parameter is used to increase or decrease the number of pods that make up a deployment?

Choose the correct answer:
Replicants
Nodes
Replicas
Syncs

What are labels used for?

Choose the correct answer:
Human-readable descriptions of objects. They have no other use.
Selecting objects for a variety of purposes.
Setting the image version number on a container in a pod. They have no other use.
Setting environment variables in the container on a pod.

You are writing YAML for a pod, and want to limit its CPU utilization to one quarter of the CPU. Which of the following lines will most likely be in your final YAML file? (Ignore whitespace)

Choose the correct answer:
cpu: "1:4"
cpu: "0.250m"
cpu: "250m"
cpu: "25"

Which of these is the best use case for a DaemonSet?

Choose the correct answer:
A monitoring back-end that only needs intermittent network access.
A MariaDB/Galera cluster that must autoscale depending on CPU utilization.
A CNI container that needs to run on every node in order to function properly.
A stateless web-head that will be load-balanced among many nodes.

Which of these commands would scale up a deployment called "soup" from 3 pods to 5?

Choose the correct answer:
kubectl scale --replicas=5 deployment/soup
kubectl scale --current-replicas 3 --replicas 5 ds soup
kubectl scale --current-replicas=3 --replicas=5 ds/soup
kubectl scale --replicas=3 soup

Which of these is a difference between annotations and labels in Kubernetes?

Choose the correct answer:
Labels are used to select and identify objects. Annotations are not.
Annotations use a key/value pair config map.
Labels allow a wider variety of characters to be used in their names than annotations.
They are the same thing.


###> Answers

1) Is it possible to configure an application in a container from Kubernetes? If so, how is this accomplished?

Correct

Correct answer
Yes, through the use of environment variables. These can be set in the YAML file for the appropriate pod.

Explanation
Environment variables all the way. These get set up in the YAML file and passed through to the container so that applications running inside have access to the relevant information.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1424/lesson/1/module/155

2) I have a deployment called "healer" running on my cluster. I look at the pods on a node and notice that there are two pods running there -- "healer-xxxxxxxx-yyyy" and "healer-xxxxxxxx-yyyz". What will happen if I issue the command "kubectl delete pod healer-xxxxxxxx-yyyz"?

Correct

Correct answer
The pod will be deleted, but the deployment will immediately spin up another pod to replace it, possibly on another node.

Explanation
The power of Kubernetes is that it self-heals, even if the administrator is unknowingly (or knowingly) taking down pods in a deployment.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1424/lesson/1/module/155

3) Which of these is the correct hierarchy of related Kubernetes API objects?

Incorrect

Correct answer
Pods make up deployments. Services point to deployments.

Explanation
Pods are the simplest Kubernetes API object. Deployments manage pods. Services point to deployments.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1424/lesson/1/module/155

4) There are many ways to assign a pod to a particular node, but they all involve the use of what?

Incorrect

Correct answer
labels

Explanation
They all use labels. Kubectl was a red herring. Remember, you *could* do this using Kubernetes API calls and not use kubectl at all. :)

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1427/lesson/1/module/155

5) Which parameter is used to increase or decrease the number of pods that make up a deployment?

Correct

Correct answer
Replicas

Explanation
The number of replicas tells K8s how many pods to keep running at all times. It's easy to scale applications up and down using replicas.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1424/lesson/1/module/155

6) What are labels used for?

Correct

Correct answer
Selecting objects for a variety of purposes.

Explanation
Labels are incredibly useful tools! They can be used to select pods for networking policies, select all the pods serving a particular app, or any other way you might need to group your pods together. Careful and thoughtful application of labels makes managing large deployments easy.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1426/lesson/1/module/155

7) You are writing YAML for a pod, and want to limit its CPU utilization to one quarter of the CPU. Which of the following lines will most likely be in your final YAML file? (Ignore whitespace)

Incorrect

Correct answer
cpu: "250m"

Explanation
250m stands for 250 millicpus, which works out to 1/4 of a running CPU.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1427/lesson/1/module/155

8) Which of these is the best use case for a DaemonSet?

Correct

Correct answer
A CNI container that needs to run on every node in order to function properly.

Explanation
DaemonSets are most useful for deploying pods on every node (or selecting specific nodes to run the pods on).

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1427/lesson/1/module/155

9) Which of these commands would scale up a deployment called "soup" from 3 pods to 5?

Correct

Correct answer
kubectl scale --replicas=5 deployment/soup

Explanation
"ds" is the short form for DaemonSets, not deployments! You don't *have* to use the current-replicas flag, and if you do, remember that it will *only* scale up the deployment *if* the current number of replicas matches that number.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1424/lesson/1/module/155

10) Which of these is a difference between annotations and labels in Kubernetes?

Correct

Correct answer
Labels are used to select and identify objects. Annotations are not.

Explanation
Both use key/value pair config maps, and annotations allow for a wider variety of characters that labels do not allow.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1426/lesson/1/module/155


# Quiz: Scheduling


When an API request is made to create a pod, which piece determines which node will be used to instantiate the new pod?

Choose the correct answer:
The scheduler
The Kubelet on the target node
The API Server itself
kube-proxy finds a free node


If a pod requests more resources than is available on any given node, what happens?

Choose the correct answer:
The pod will not be scheduled until a node with the resources becomes available.
The scheduler will return an error.
The pod will get scheduled on the master node.
The pod will move into a "NotReady" status.

What are taints and what are they applied to?

Choose the correct answer:
Taints are used to mark a pod as unavailable during an outage and are applied to pods.
Taints are used to repel workloads from one another (anti-affinity) and are applied to pods.
Taints are used to repel certain pods from nodes and are applied to nodes.
Taints are used to repel workloads with certain labels and are applied to nodes and pods.

Question 4 of 10

Why are annotations particularly important when using multiple or custom schedulers?

Choose the correct answer:
Because they can remind operators which scheduler was used to place (or fail to place) a pod.
Because they are the only audit trail available for the scheduler.
Because multiple schedulers are not allowed without annotations because of the security risk.
Because they are how the scheduler is specified.

Question 5 of 10

How can a user specify which scheduler a pod should use?

Choose the correct answer:
Through the scheduler-name tag in the spec.
By adding a schedulerName=*scheduler* annotation to the metadata.
Through the schedulerName tag in the spec.
By adding a schedule=custom label to the metadata.


Question 6 of 10


What is the scheduler?

Choose the correct answer:
A pod on the master node.
A distributed DaemonSet on the cluster.
An isolated, non-containerized process on the master node.
A subprocess of the CNI.


Question 7 of 10

Why might a user desire two pods to have anti-affinity?

Choose the correct answer:
She wants them to run on the same node to speed up networking traffic between them.
She wants them to share memory space on a node.
She wants them to run on different nodes to avoid sharing failure domains.
She wants them to be on network adjacent nodes for faster shared disk access.

Question 8 of 10



What is podAffinity used for?

Choose the correct answer:
Allowing nodes with containers in the same pod access to a higher-speed network.
Preventing two pods from being placed on the same node.
Placing two or more pods on the same node.
Ensuring replicated pods in the same deployment are placed on different nodes.

Question 9 of 10

If a toleration and a taint match during scheduling, what happens?

Choose the correct answer:
An error — taints and tolerations cannot be used together in the same namespace.
The toleration is ignored and the node might be scheduled for uncordon.
The taint is ignored and the pod might be scheduled to the node.
The toleration and taint reinforce one another, further guaranteeing that the pod is not scheduled on the node.

Question 10 of 10

How can a pod be assigned to a specific node?

Choose the correct answer:
Set node constraints in the node's YAML.
Using a nodeSelector with properly labelled nodes.
Use the host property in the pod's YAML.
The scheduler does not allow for pods to be placed manually.


#### QUIZ RESULTS: SCHEDULING

FAIL


IMPORTANT: TO INCREASE YOUR CHANCES OF SUCCESS, DO NOT ONLY REVIEW THE CORRECT ANSWERS, BUT GO BACK TO THE COURSE MATERIALS TO ENSURE A COMPLETE UNDERSTANDING OF THE TOPIC.

1) When an API request is made to create a pod, which piece determines which node will be used to instantiate the new pod?

Correct

Correct answer
The scheduler

Explanation
The scheduler is what determines which pods go with which nodes.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1428/lesson/1/module/155

2) If a pod requests more resources than is available on any given node, what happens?

Incorrect

Correct answer
The pod will not be scheduled until a node with the resources becomes available.

Explanation
The pod will remain in a "Pending" status until a node becomes available -- which might be never.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1428/lesson/1/module/155

3) What are taints and what are they applied to?

Correct

Correct answer
Taints are used to repel certain pods from nodes and are applied to nodes.

Explanation
Taints allow a node to repel a set of pods.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1428/lesson/1/module/155

4) Why are annotations particularly important when using multiple or custom schedulers?

Correct

Correct answer
Because they can remind operators which scheduler was used to place (or fail to place) a pod.

Explanation
Annotations are designed to provide additional non-identifying information about a pod, and things like application version or scheduler that placed the pod are ideal uses for these.

Further Reading
https://linuxacademy.com/cp/exercises/view/id/669/module/155

5) How can a user specify which scheduler a pod should use?

Incorrect

Correct answer
Through the schedulerName tag in the spec.

Explanation
The tag for specifying a particular scheduler is schedulerName and defaults to default-scheduler.

Further Reading
https://linuxacademy.com/cp/exercises/view/id/669/module/155

6) What is the scheduler?

Incorrect

Correct answer
A pod on the master node.

Explanation
The scheduler is a process that runs in a pod, usually on the master node. While it's unusual, it's possible to have multiple schedulers running on the same cluster.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1428/lesson/1/module/155

7) Why might a user desire two pods to have anti-affinity?

Correct

Correct answer
She wants them to run on different nodes to avoid sharing failure domains.

Explanation
Anti-affinity means that two pods will not run on the same node, and is usually implemented to prevent two pods from being in the same failure domain in case something goes wrong.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1428/lesson/1/module/155

8) What is podAffinity used for?

Incorrect

Correct answer
Placing two or more pods on the same node.

Explanation
Placing two or more pods on the same node is done with the podAffinity attribute and uses labels.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1428/lesson/1/module/155

9) If a toleration and a taint match during scheduling, what happens?

Incorrect

Correct answer
The taint is ignored and the pod might be scheduled to the node.

Explanation
Taints and tolerations work together to ensure that pods are not scheduled onto inappropriate nodes. One or more taints are applied to a node; this marks that the node should not accept any pods that do not tolerate the taints. Tolerations are applied to pods, and allow (but do not require) the pods to schedule onto nodes with matching taints.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1428/lesson/1/module/155

10) How can a pod be assigned to a specific node?

Correct

Correct answer
Using a nodeSelector with properly labelled nodes.

Explanation
Using the nodeSelector is the easiest way to manually assign pods to nodes.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1430/lesson/1/module/155


## Quiz: Logging/Monitoring

Question 1 of 10


Is it possible to get a shell prompt to a Ubuntu 16.04 based container called "sidecar1" in the pod "star-aaaaaaaaaa-bbbbb"? There are several containers in the pod. If so, how?

Choose the correct answer:
Yes! kubectl exec -it star-aaaaaaaaaa-bbbbb/sidecar1 -- /bin/bash
Yes! kubectl run star-aaaaaaaaaa-bbbbb sidecar1 -- /bin/bash
No. This is only possible when there is a single container in the pod.
Yes! kubectl exec -it star-aaaaaaaaaa-bbbbb --container sidecar1 -- /bin/bash

Question 2 of 10

Where does the Kubernetes key/value store (etcd) log file reside?

Choose the correct answer:
On the host in /etc/kubernetes/etcd.log
On the host in /var/syslog
On the host in /var/log/kubernetes/etcd
On the host in /var/log/pods


Question 3 of 10

I'm troubleshooting an application issue and would love to see the application's logs, which are in a file in the container "appctn" in the pod "apppod-abcdef123-45678" at /var/log/applog. Which of these commands would list that for me?

Choose the correct answer:
kubectl logs apppod-abcdef123-45678
kubectl logs apppod-abcdef123-45678 -c appctn
kubectl logs -c appctn
kubectl exec apppod-abcdef123-45678 -- cat /var/log/applog

Question 4 of 10

I have a node called "node8" and I'd like to know what kind of load it's under including the CPU and Memory requests. Which of these commands would give me that information?

Choose the correct answer:
kubectl describe node node8
kubectl describe deployments --all-namespaces --with-nodes
kubectl get nodes --status{cpu.requests}&&{memory.requests}
kubeadm status node8

Question 5 of 10

Is it possible to get the logs back from a dead or evicted pod? If so, how?

Choose the correct answer:
Yes, restart the dead pod in safe mode and extract the file through scp or sftp.
No, once a pod is gone, all of its ephemeral storage is gone.
Yes, if the node is immediately cordoned, you can use the --inspect flag.
Yes, add the --previous flag to the kubectl logs command.

Question 6 of 10

What's an easy command to check the health and status of your cluster?

Choose the correct answer:
kubectl get nodes
kubectl cluster-status
kubectl create -f status
kubeadm k8s-status

Question 7 of 10

What's the recommended method for dealing with applications that insist on writing out logs to a file rather than being able to redirect them to stdout?

**Choose the correct answer:** 

* Do without logging.
* Find a logging agent that can operate inside the pod and send the logs to a central file store or log aggregator.
* Don't use Kubernetes.
* Redirect the log file to ephemeral storage on the host.

Question 8 of 10

Which log command will show you just the final 8 lines of stdout for a pod?

Choose the correct answer:
kubectl logs --tail=8
kubectl logs tail 8
kubectl logs -8
kubectl get logs --tail=8

Question 9 of 10

Starting with Kubernetes 1.8, there is a new metrics API. This can be accessed directly from the command line with which command?

Choose the correct answer:
heapster get info
kubectl metrics [nodes | pods]
cadvisor list
kubectl top [nodes | pods]

Question 10 of 10

Which command will give you stdout of a pod called "to-the-screen"?

**Choose the correct answer:**
* kubectl get logs po to-the-screen
* kubectl logs to-the-screen
* kubectl logs -f to-the-screen.yaml
* kubectl exec -it to-the-screen -- kube-get-stdout

###> Answers


FAIL


IMPORTANT: TO INCREASE YOUR CHANCES OF SUCCESS, DO NOT ONLY REVIEW THE CORRECT ANSWERS, BUT GO BACK TO THE COURSE MATERIALS TO ENSURE A COMPLETE UNDERSTANDING OF THE TOPIC.

1) Is it possible to get a shell prompt to a Ubuntu 16.04 based container called "sidecar1" in the pod "star-aaaaaaaaaa-bbbbb"? There are several containers in the pod. If so, how?

Incorrect

Correct answer
Yes! kubectl exec -it star-aaaaaaaaaa-bbbbb --container sidecar1 -- /bin/bash

Explanation
While it's discouraged in Kubernetes, it's still possible to get to a container's shell. It's generally considered a bad idea to do things like alter configuration files or apt-get files while logged in. Its use should be limited to debugging when possible.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1432/lesson/1/module/155

2) Where does the Kubernetes key/value store (etcd) log file reside?

Incorrect

Correct answer
On the host in /var/log/pods

Explanation
The Kubernetes services that run in pods on the host store their logs in /var/log/pods

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1434/lesson/1/module/155

3) I'm troubleshooting an application issue and would love to see the application's logs, which are in a file in the container "appctn" in the pod "apppod-abcdef123-45678" at /var/log/applog. Which of these commands would list that for me?

Incorrect

Correct answer
kubectl exec apppod-abcdef123-45678 -- cat /var/log/applog

Explanation
kubectl logs only work for STDOUT, so if your logs are elsewhere, you'll need to pull them with something like the command here.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1432/lesson/1/module/155

4) I have a node called "node8" and I'd like to know what kind of load it's under including the CPU and Memory requests. Which of these commands would give me that information?

Incorrect

Correct answer
kubectl describe node node8

Explanation
kubectl describe node will give you all kinds of very useful up to date information about a given node.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1432/lesson/1/module/155

5) Is it possible to get the logs back from a dead or evicted pod? If so, how?

Incorrect

Correct answer
Yes, add the --previous flag to the kubectl logs command.

Explanation
To grab the last logs, just add --previous!

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1432/lesson/1/module/155

6) What's an easy command to check the health and status of your cluster?

Correct

Correct answer
kubectl get nodes

Explanation
Kubectl get nods will show you at a glance which of your nodes are ready and which might be having troubles. It's a great first stop if you suspect trouble.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1434/lesson/1/module/155

7) What's the recommended method for dealing with applications that insist on writing out logs to a file rather than being able to redirect them to stdout?

Correct

Correct answer
Find a logging agent that can operate inside the pod and send the logs to a central file store or log aggregator.

Explanation
It's usually a fairly easy task to incorporate a logging handler and central location for log files within the cluster.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1434/lesson/1/module/155

8) Which log command will show you just the final 8 lines of stdout for a pod?

Correct

Correct answer
kubectl logs --tail=8

Explanation
Two hyphens and an equal, unless you want exactly ten lines, then it's just kubectl logs --tail

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1434/lesson/1/module/155

9) Starting with Kubernetes 1.8, there is a new metrics API. This can be accessed directly from the command line with which command?

Incorrect

Correct answer
kubectl top [nodes | pods]

Explanation
kubectl top, along with the object you'd like to watch, gives some in-depth information right on the command line. Who needs a GUI?

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1432/lesson/1/module/155

10) Which command will give you stdout of a pod called "to-the-screen"?

Correct

Correct answer
kubectl logs to-the-screen

Explanation
kube logs is the fastest way to get stdout and the recommended, standard way to configure your applications in containers to handle their logs.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1434/lesson/1/module/155

# Quiz: Networking

Question 1 of 10

Ingress is fairly new to the Kubernetes stack. What version number was the first one to include it?

Choose the correct answer:
1.8
1.1
1.5
1.0

Question 2 of 10

What is required to specify a service type of "LoadBalancer"?

Choose the correct answer:
A cloud provider that supports Kubernetes-provisioned load balancers.
Three or more pods in a deployment.
A pod to check the health of the other pods.
Nothing -- it's built in.

Question 3 of 10

Think about the YAML for a network policy. If you had to create one, what is the pattern?

Choose the correct answer:
Preamble, podSelector, hosts, ingress rules, egress rules
Preamble, host, podSelector, ingress, and/or egress rules
Preamble, podSelector, ingress, and/or egress rules
Preamble, ingress rules, host(s), egress rules, host(s)


Question 4 of 10

When a service type of "ClusterIP" is used, what is the result?

Choose the correct answer:
An IP address in a specialized bridge network that links the external network to the internal cluster network.
A port on the node where the pod resides, usually above 30000.
A single IP address within the cluster that redirects traffic to a pod (possibly on a different node) serving the application (the pod).
An single IP address external to the cluster that is drawn from a pool of available public addresses.

Question 5 of 10

What handles inter-pod communication?

Choose the correct answer:
Host networking
VLANs
GRE tunnels
The CNI

Question 6 of 10

What is an Ingress as it relates to Kubernetes?

Choose the correct answer:
A method of routing control-plane instructions to the master node.
An API object that manages external access to the services in a cluster, usually HTTP.
An API object that creates a services load balancer to access services in the cluster from alternate nodes.
A port on the master where containers are mapped to pods.

Question 7 of 10

For a user to be able to request an Ingress resource, what must the cluster have?

Choose the correct answer:
A DaemonSet of redis for storing configuration information.
A CNI that supports Ingress.
An iSCSI volume to store configuration information.
An Ingress controller compatible with available and appropriate service providers like load balancers.

Question 8 of 10


What determines how a set of pods are allowed communicate with one another and other network endpoints?

Choose the correct answer:
Network Policies
PVCs
Ingress
RBACs

Question 9 of 10


If a service called "web-head" is exposed in the default namespace, then other pods can resolve it using all of these hostnames except which?

Choose the correct answer:
web-head.default
web-head
All of these will resolve properly.
web-head.local

Question 10 of 10

If an Ingress request is made with no associated rules, what happens?

Choose the correct answer:
All traffic is forbidden in the namespace except to the named host.
All traffic is forbidden in the namespace.
All traffic is sent to a single host.
The request fails and no Ingress is created. Rules are required.

### Result


FAIL


IMPORTANT: TO INCREASE YOUR CHANCES OF SUCCESS, DO NOT ONLY REVIEW THE CORRECT ANSWERS, BUT GO BACK TO THE COURSE MATERIALS TO ENSURE A COMPLETE UNDERSTANDING OF THE TOPIC.

1) Ingress is fairly new to the Kubernetes stack. What version number was the first one to include it?

Correct

Correct answer
1.1

Explanation
v1.1 of Kubernetes included the Ingress API object and it's been constantly improved and increasingly used ever since.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1443/lesson/1/module/155

2) What is required to specify a service type of "LoadBalancer"?

Incorrect

Correct answer
A cloud provider that supports Kubernetes-provisioned load balancers.

Explanation
The "LoadBalancer" service type only works on cloud providers that support it. Minikube will also allow it but does not create a full, production-quality load balancer.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1441/lesson/1/module/155

3) Think about the YAML for a network policy. If you had to create one, what is the pattern?

Incorrect

Correct answer
Preamble, podSelector, ingress, and/or egress rules

Explanation
Preamble contains apiVersion, Kind, and Metadata; then comes the podSelector to determine which pods this policy oversees; and, finally, the rules.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1441/lesson/1/module/155

4) When a service type of "ClusterIP" is used, what is the result?

Incorrect

Correct answer
A single IP address within the cluster that redirects traffic to a pod (possibly on a different node) serving the application (the pod).

Explanation
ClusterIP is most commonly used with third-party load balancers.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1439/lesson/1/module/155

5) What handles inter-pod communication?

Correct

Correct answer
The CNI

Explanation
The CNI (Container Network Interface) allows pods to communicate with one another within a cluster regardless of which node they are on.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1439/lesson/1/module/155

6) What is an Ingress as it relates to Kubernetes?

Correct

Correct answer
An API object that manages external access to the services in a cluster, usually HTTP.

Explanation
A fairly new concept in Kubernetes, an Ingress allows us to abstract away the implementation details of routes into the cluster, such as Load Balancers.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1443/lesson/1/module/155

7) For a user to be able to request an Ingress resource, what must the cluster have?

Correct

Correct answer
An Ingress controller compatible with available and appropriate service providers like load balancers.

Explanation
With Kubernetes, the general rule of thumb is that YAML requests will return successfully, but if there is no service to fulfill it then the request will have no effect.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1443/lesson/1/module/155

8) What determines how a set of pods are allowed communicate with one another and other network endpoints?

Correct

Correct answer
Network Policies

Explanation
Network policies determine what traffic gets into and out of a pod. The CNI must support them, though, but most of them do.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1443/lesson/1/module/155

9) If a service called "web-head" is exposed in the default namespace, then other pods can resolve it using all of these hostnames except which?

Incorrect

Correct answer
web-head.local

Explanation
The .local won't work!

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1444/lesson/1/module/155

10) If an Ingress request is made with no associated rules, what happens?

Incorrect

Correct answer
All traffic is sent to a single host.

Explanation
This is a useful way of setting up common error pages, such as the location of a unified 404 page.

Further Reading
https://linuxacademy.com/cp/courses/lesson/course/1443/lesson/1/module/155

