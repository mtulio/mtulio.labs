
```mermaid
graph  LR
  role<-.->config
  stsservice<-- AssumeRoleWithWebIdentity/JWT -.->Pod
  Pod-- Creds Assumed Role -->serviceapi
  subgraph cluster [AWS]
    CloudFront[CloudFront Distribution];
    S3Bucket[S3 Bucket w/ OIDC Config];
    iam_idp-- Public URL -->S3Bucket;
    iam_idp-- Public URL -->CloudFront;
    CloudFront-- Private access -->S3Bucket;
    stsservice -- Trust Tokens<br>Signed -->iam_idp;
    role<-->stsservice;
    subgraph AWS_IAM;
      role[IAM Role For Pod];
      iam_idp[IAM Identity Provider/OIDC];
    end
    subgraph AWS_API;
      stsservice[AWS STS API];
      serviceapi[AWS Service API/EC2,S3...];
    end
  end
  subgraph cluster2 [OpenShift]
    sa([ServiceAccount Signing Keys]) -- Public <br> Key -->KAS_HTTP;
    sa([ServiceAccount Signing Keys]) -- Private <br> Key -->token_signing;
    sa
    token_signing[Token Signing]-->projected[Projected<br>ServiceAccount<br>Token];
    subgraph KAS;
      KAS_HTTP
      KAS_OIDC[OIDC configs/JWKS]
      KAS_HTTP -- /.well-known/openid-configuration -->KAS_OIDC
      KAS_HTTP -- /openid/v1/jwks -->KAS_OIDC
    end
    subgraph Pod
    config[AWS Config File]-->projected
  end
  end
  classDef plain fill:#ddd,stroke:#fff,stroke-width:4px,color:#000;
  classDef k8s fill:#326ce5,stroke:#fff,stroke-width:4px,color:#fff;
  classDef cluster fill:#fff,stroke:#bbb,stroke-width:2px,color:#326ce5;
  classDef cluster2 fill:#fff,stroke:#bbb,stroke-width:2px,color:#326ce5;
  class config,role,stsservice,serviceapi,projected,token_signing,iam_idp,pod1,pod2,S3Bucket,CloudFront,KAS_HTTP,KAS_OIDC k8s;
  class sa plain;
  class cluster cluster;
  class cluster2 cluster1;
```
