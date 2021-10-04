# Red Hat Certified Specialist in Advanced Automation: Ansible Best Practices exam

Reference:
- [Exame page](https://www.redhat.com/en/services/training/ex447-red-hat-certified-specialist-advanced-automation-ansible-best-practices-exam?section=Objectives)

NOTE:
- This is not a certification sguide, this is a group of notes based on public objectives.

## Objectives

Understand and use Git
- Clone a Git repository
- Update, modify and create files in a Git repository
- Add those modified files back into the Git repository

Manage inventory variables
- Structure host and group variables using multiple files per host or group
- Use special variables to override the host, port, or remote user Ansible uses for a specific host
- Set up directories containing multiple host variable files for some of your managed hosts
- Override the name used in the inventory file with a different name or IP address

Manage task execution
- Control privilege execution
- Run selected tasks

Transform data with filters and plugins
- Populate variables with data from external sources using lookup plugins
- Use lookup and query functions to template data from external sources into playbooks and deployed template files
- Implement loops using structures other than simple lists using lookup plugins and filters
- Inspect, validate, and manipulate variables containing networking information with filters

Delegate tasks
- Run a task for a managed host on a different host, then control whether facts gathered by that task are delegated to the managed host or the other host

Install Ansible Tower
- Perform basic configuration of Ansible Tower after configuration

Manage access for Ansible Tower
- Create Ansible Tower users and teams and make associations of one to the other

Manage inventories and credentials
- Manage advanced inventories
- Create a dynamic inventory from an identity management server or a database server
- Create machine credentials to access inventory hosts
- Create a source control credential

Manage projects
- Create a job template

Manage job workflows
- Create a job workflow template

Work with the Ansible Tower API
- Write an API scriptlet to launch a job

Back up Ansible Tower
- Back up an instance of Ansible Tower