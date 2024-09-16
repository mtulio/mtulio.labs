#!/usr/bin/env python
import argparse
import os
import json
import glob
import gzip
import yaml


class Events(object):
    """
    Store the Principal and Event information.
    """
    def __init__(self):
        self.iam_events = {}
        self.processed_files = []

    def insert_principal(self, provider, principal_name, principal_type):
        if principal_name not in self.iam_events:
            self.iam_events[principal_name] = {
                "provider": provider,
                "name": principal_name,
                "type": principal_type,
                "events": {},
            }
        return

    def insert_event(self, principal_id, event, event_params={}, creates=None):
        if principal_id not in self.iam_events:
            self.insert_principal("unknown", principal_id, "unknown")
        if event not in self.iam_events[principal_id]['events']:
            self.iam_events[principal_id]['events'][event] = {
                'count': 0,
                # 'params': {},
            }
        self.iam_events[principal_id]['events'][event]['count'] += 1

        # Save parameters
        # if event_params is not None and len(event_params) > 0:
        #     param_id = str(hash(str(event_params)))
        #     if param_id not in self.iam_events[principal_id]['events'][event]['params']:
        #         self.iam_events[principal_id]['events'][event]['params'][param_id] = event_params

        # Save creates
        # creates are user names created by the principal
        if creates is not None:
            if 'creates' not in self.iam_events[principal_id]:
                self.iam_events[principal_id]['creates'] = []
            self.iam_events[principal_id]['creates'].append(creates)
        return

class CloudCredentialsReport(object):
    """
    Parse the CloudTrail or Azure Monitor logs to extract Principal and Event information.
    """
    def __init__(self, output_dir, filters=None):
        self.output_dir = output_dir
        self.filters = self.create_filters(filters)

        self.events = Events()
        self.filtered_events = None
        self.processed_files = []

    def create_filters(self, filters):
        if filters is None:
            return None
        finalFilters = {}
        for f in filters.split(','):
            key, value = f.split('=')
            finalFilters[key] = value
        return finalFilters

    def parse_events(self, event_path):
        # Discover all the log files paths
        log_files = glob.glob(os.path.join(event_path, '**/*.json.gz'), recursive=True)
        log_files += glob.glob(os.path.join(event_path, '**/*.json'), recursive=True)
        # print(log_files)
        for log_file in log_files:
            data = ''
            cloud_provider="TBD"
            # print(f'Processing {log_file}')
            if log_file.endswith('.json.gz'):
                # print(f'Processing .json.gz')
                with gzip.open(log_file, 'rb') as f:
                    compressed_content = f.read()
                    # decompressed_content = gzip.decompress(compressed_content)
                    content = compressed_content.decode('utf-8')
                    data = json.loads(content)

            elif log_file.endswith('.json'):
                with open(log_file, 'r') as f:
                    data = {
                        "events": []
                    }
                    for line in f.readlines():
                        data['events'].append(json.loads(line))
                    # data = json.loads(f.read())

            # Discover the cloud provider
            ## AWS
            if data.get('Records', None):
                cloud_provider = 'AWS'
            elif data.get('events', None):
                cloud_provider = 'Azure'
            else:
                log.Error(f'Unknown cloud provider for {log_file}')
                continue

            # Parse the log file
            pfile = {
                'file': log_file,
                'cloud_provider': cloud_provider,
            }
            if cloud_provider == 'AWS':
                res = self.parse_aws(data)
            elif cloud_provider == 'Azure':
                res = self.parse_azure(data)
            else:
                pfile['result'] = 'error'
                pfile['error'] = 'Unknown cloud provider'
                self.processed_files.append(pfile)
                log.Error(f'Unknown cloud provider for {log_file}')
                continue

            pfile['result'] = 'success'
            if res:
                pfile['result'] = 'success'
                pfile['stat'] = {
                    'total': res['total'],
                    'processed': res['processed'],
                    'skipped': res['skipped'],
                }
            self.processed_files.append(pfile)

        self.post_processor()
        return

    def parse_aws(self, data):
        """
        Parse the CloudTrail log data to extract Principal and Event information.
        """
        res = {
            'total': 0,
            'processed': 0,
            'skipped': 0,
        }
        for event in data.get('Records', []):
            # Check if userIdentity.type is IAMUser or AssumedRole
            res['total'] += 1
            user_type = event['userIdentity'].get('type', '')
            if user_type in ['IAMUser']:
                # Check if userIdentity.UserName prefixes with cluster_name
                user_id = event['userIdentity'].get('userName', '')
                # Extract the eventSource and eventName
                event_id = (f'{event.get('eventSource', '').replace('.amazonaws.com', '')}:{event.get('eventName', '')}')
                event_params = ''
                if 'requestParameters' in event:
                    event_params = event['requestParameters']

                # Group the eventSource and eventName by userIdentity.userName
                self.events.insert_principal("AWS", user_id, user_type)

                # Process specific events
                creates = None
                if event_id == "iam:CreateUser" and event_params.get('userName', None):
                    creates = event_params.get('userName', None)
                self.events.insert_event(user_id, event_id, event_params=event_params, creates=creates)

            # Group by AssumedRole type
            elif user_type in ['AssumedRole']:
                # role_name = event['userIdentity'].get('arn', '')
                user_id = event['userIdentity'].get('sessionContext', {}).get('sessionIssuer', {}).get('userName', '')
                event_id = (f'{event.get('eventSource', '').replace('.amazonaws.com', '')}:{event.get('eventName', '')}')

                self.events.insert_principal("AWS", user_id, user_type)
                self.events.insert_event(user_id, event_id)
            
            else:
                res['skipped'] += 1
                continue

            res['processed'] += 1
        return res

    def parse_azure(self, data):
        """
        Parse the Azure log data to extract Principal and Event information.
        """
        res = {
            'total': 0,
            'processed': 0,
            'skipped': 0,
        }
        if 'events' not in data:
            print("ERROR: unable to find events")
            return

        for event in data['events']:
            res['total'] += 1
            # Check if userIdentity
            operationName = event.get('operationName', '')
            action = event.get('identity', {}).get('authorization', {}).get('action', '')
            event_id = action
            # evemt_params = event.get('parameters', {})

            principal_type = event.get('identity', {}).get('authorization', {}).get('evidence', {}).get('principalType', '')
            principal_id = event.get('identity', {}).get('authorization', {}).get('evidence', {}).get('principalId', '')

            if event_id == "":
                event_id = operationName

            self.events.insert_principal("Azure", principal_id, principal_type)
            self.events.insert_event(principal_id, event_id, event_params={})
            res['processed'] += 1
        return res

    def post_processor(self):
        """
        Post process the events data.
        """

        # Discover identity which created another identity
        for principal_id in self.events.iam_events:
            if 'creates' in self.events.iam_events[principal_id]:
                for user_id in self.events.iam_events[principal_id]['creates']:
                    if user_id in self.events.iam_events:
                        if 'created_by' in self.events.iam_events[user_id]:
                            log.Warning(f'User {user_id} already has created_by')
                            continue
                        if 'created_by' not in self.events.iam_events[user_id]:
                            self.events.iam_events[user_id]['created_by'] = principal_id
        return

    def apply_filters(self):
        """
        Apply filters to the events data.
        """
        self.filtered_events = Events()
        if self.filters is None:
            self.filtered_events.iam_events = self.events.iam_events
            return

        # Apply filter installer-user
        if 'principal-name' in self.filters:
            if self.filters['principal-name'] in self.events.iam_events:
                self.filtered_events.iam_events[self.filters['principal-name']] = self.events.iam_events[self.filters['principal-name']]

        # Apply filter cluster-id
        if 'principal-prefix' in self.filters:
            for principal_id in self.events.iam_events:
                if principal_id.startswith(self.filters['principal-prefix']):
                    self.filtered_events.iam_events[principal_id] = self.events.iam_events[principal_id]

        # Apply filter for cloud provider
        if 'cloud-provider' in self.filters:
            for principal_id in self.events.iam_events:
                if self.events.iam_events[principal_id]['provider'] == self.filters['cloud-provider']:
                    self.filtered_events.iam_events[principal_id] = self.events.iam_events[principal_id]
        return

    def save(self):
        self.apply_filters()

        file = f"{self.output_dir}/events.json"
        with open(file, 'w') as f:
            f.write(json.dumps(self.filtered_events.iam_events, indent=2))
        print(f'Events saved to {file}')

        file = f"{self.output_dir}/file_status.json"
        with open(file, 'w') as f:
            f.write(json.dumps(self.events.processed_files, indent=2))
        print(f'File status saved to {file}')


class CloudCredentialsRequests(CloudCredentialsReport):
    """
    Compare the IAM events with the CredentialsRequests to identify the missing permissions.
    """
    def __init__(self, output_dir, credentials_requests_path, filters=None):
        super().__init__(output_dir, filters)
        self.credentials_requests_path = credentials_requests_path
        self.credentials_requests = {}
        self.compiled_users = {
            "users": {
                "notFound": [],
            }
        }

    def load_events(self, events_path):
        with open(events_path, 'r') as f:
            self.events.iam_events = json.load(f)
        return

    def load_credentials_requests(self):
        # Discover all the log files paths
        log_files = glob.glob(os.path.join(self.credentials_requests_path, '**/*.yaml'), recursive=True)
        for log_file in log_files:
            data = ''
            with open(log_file, 'r') as f:
                data = yaml.safe_load(f)
            self.credentials_requests[log_file] = data
        return

    def compare(self):
        for principal_id in self.events.iam_events:
            # Check if cluster-name filter has been added, otherwise skip.
            if 'cluster-name' not in self.filters:
                raise Exception('cluster-name filter is required to discover the expected userName by CredentailsRequests. Username is the metadata.name added in install-config.yaml. Set it and try again.')

            print(f'Processing {principal_id}')
            if principal_id not in self.compiled_users['users']:
                self.compiled_users['users'][principal_id] = {
                    'required': sorted(list(self.events.iam_events[principal_id]['events'].keys())),
                }

            # Normalize the principal_id
            # In general the cluster identifier is the well known name (metadata.name) plus a random suffix,
            # as known as ClusterID. The ClusterID is used as prefix of identitied created
            # by CCC (Cloud Credential Controller). The CCO also adds a suffix to the user name,
            # those parts must be removed to try to match the credential name of CredentialsRequests object.
            # Example of credential (IAM User) created by CCO on cluster-name 'mycluster',
            # ClusterID 'mycluster-abc123', for openshift-image-registry credential:
            # mycluster-abc123-openshift-image-registry-xyq987
            # ^ The identifier must be transformed to openshift-image-registry.
            normalized_principal_id = principal_id.replace(f"{self.filters['cluster-name']}-", '')
            parts = normalized_principal_id.split('-')[:-1][1:]
            normalized_principal_id = '-'.join(parts)

            print(f'Processing {principal_id} => {normalized_principal_id}')
            if normalized_principal_id == '':
                continue

            # Additional information: Sometimes the IAM principal must be truncated by CCO, the
            # operation is comparing the initial words to try to make the inference.
            print(f'Processing {principal_id} => {normalized_principal_id} => {self.filters["cluster-name"]}')
            if not principal_id.startswith(self.filters['cluster-name']):
                continue

            # Iteract over the credential requests to find the expected principal
            for credReq in self.credentials_requests.keys():
                print(f'Processing {principal_id} => {normalized_principal_id} => {credReq}')
                # Get expected userName from the credentials requests
                credReq_principal = self.credentials_requests.get(credReq, {}).get('metadata', {}).get('name', '')

                if not credReq_principal.startswith(normalized_principal_id):
                    continue

                self.compiled_users['users'][principal_id]['requested'] = []
                # extract required permissions for CredentialsRequests
                manifest = self.credentials_requests.get(credReq, {})
                allowEntries = manifest.get('spec', {}).get('providerSpec', {}).get('statementEntries', [])
                diff = {
                    'missing': [],
                    'extra': [],
                }
                for entry in allowEntries:
                    # skip when specific actions are Deny (not supported)
                    if entry.get('effect', '') != "Allow":
                        continue
                    for action in entry.get('action', []):
                        if action not in self.compiled_users['users'][principal_id]['requested']:
                            self.compiled_users['users'][principal_id]['requested'].append(action)
                        # Calculate extra permissions:
                        star = False
                        if '*' in action:
                            # Too much open permissions. Should have at least the service definitoin.
                            if ':' not in action:
                                diff['unwanted'].append(action)
                            else:
                                star = True
                                action = action.replace('*', '')
                        if star and action not in self.compiled_users['users'][principal_id]['required']:
                            diff['extra'].append(action)
                        elif action not in self.compiled_users['users'][principal_id]['required']:
                            diff['extra'].append(action)

                # end CredRequest
                self.compiled_users['users'][principal_id]['diff'] = diff
                self.compiled_users['users'][principal_id]['credRequestRef'] = credReq

        # calculate missing permissions:
        for principal in self.compiled_users['users']:
            if ('diff' not in self.compiled_users['users'][principal]) or ('requested' not in self.compiled_users['users'][principal]):
                continue
            for action in self.compiled_users['users'][principal]['required']:
                if action not in self.compiled_users['users'][principal]['requested']:
                    self.compiled_users['users'][principal]['diff']['missing'].append(action)
        return

    def save(self):
        file = f"{self.output_dir}/compiled_users.json"
        with open(file, 'w') as f:
            f.write(json.dumps(self.compiled_users, indent=2))
        print(f'Compiled users saved to {file}')

def main():
    # Create the argument parser
    parser = argparse.ArgumentParser(description='CLI for managing clusters')

    # Action is
    parser.add_argument('--command', help='Command to be executed. Valid values: extract|compare', required=True)

    # General options
    parser.add_argument('--output', help='Path to output file', required=False)
    
    # Options used to command extract
    parser.add_argument('--filters', help='Filters to Apply to the final results', required=False)
    parser.add_argument('--events-path', help='Path to the events (CloudTrail or Azure monitor files)', required=False)

    # Options used to command compare
    parser.add_argument('--credentials-requests-path', help='Path to CredentialsRequests Manifests', required=False)

    # Parse the command line arguments
    args = parser.parse_args()

    try:
        # Command extract
        if args.command == 'extract':
            report = CloudCredentialsReport(args.output, filters=args.filters)
            report.parse_events(args.events_path)
            report.save()
        elif args.command == 'compare':
            print('Checking credentials requests')
            report = CloudCredentialsRequests(args.output, args.credentials_requests_path, filters=args.filters)
            report.load_events(args.events_path)
            report.load_credentials_requests()
            report.compare()
            report.save()
            # compare_credentialsrequests(args)
        else:
            print(f'Unknown command {args.command}. Expected: extract|compare')
            exit(1)
    except Exception as e:
        # print(f'Error: {e}')
        # exit(1)
        raise e


if __name__ == '__main__':
    main()
